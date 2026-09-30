import CompanionCore
import CoreLocation
import Foundation
import MapKit

/// The seam over `CLLocationManager`: everything the locator asks of the
/// system, and what the system answers, so a test can play both sides.
@MainActor
protocol LocationManaging: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    var onAuthorizationChange: (@MainActor @Sendable (CLAuthorizationStatus) -> Void)? { get set }
    /// One fix, or nil when the system failed to give one.
    var onLocation: (@MainActor @Sendable (CLLocation?) -> Void)? { get set }
    func requestPermission()
    func requestLocation()
}

/// The real manager. Delegate callbacks arrive on any thread and hop to the
/// main actor before touching the locator.
@MainActor
final class SystemLocationManager: NSObject, LocationManaging, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onAuthorizationChange: (@MainActor @Sendable (CLAuthorizationStatus) -> Void)?
    var onLocation: (@MainActor @Sendable (CLLocation?) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        // A city, not a doorstep: the coarsest accuracy is also the fastest.
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }
    func requestPermission() { manager.requestWhenInUseAuthorization() }
    func requestLocation() { manager.requestLocation() }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return }
        Task { @MainActor in self.onAuthorizationChange?(status) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let first = locations.first
        Task { @MainActor in self.onLocation?(first) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        let kind = String(describing: type(of: error))
        Task { @MainActor in
            Log.app("location: fix failed (\(kind))")
            self.onLocation?(nil)
        }
    }
}

/// The system's city through CoreLocation (16h-3). The fix is asked at
/// city accuracy and reverse-geocoded to a name at once; the coordinates
/// never leave this file — not into the prompt, not into a log. Logs say
/// that a lookup happened, never where.
@MainActor
package final class CoreLocationCityLocator: UserLocating {
    typealias Sleep = @Sendable (Duration) async throws -> Void
    typealias Geocode = @Sendable (CLLocation) async -> UserLocation?

    /// The dialog waits on a person; a turn waits on nobody for this long.
    static let permissionWait: Duration = .seconds(30)
    static let fixWait: Duration = .seconds(10)
    static let geocodeWait: Duration = .seconds(10)

    private let manager: any LocationManaging
    private let sleep: Sleep
    private let geocode: Geocode
    private var permission: CheckedContinuation<Bool, Never>?
    private var permissionTimer: Task<Void, Never>?
    private var fix: CheckedContinuation<CLLocation?, Never>?
    private var fixTimer: Task<Void, Never>?

    package convenience init() {
        self.init(manager: SystemLocationManager(), sleep: { try await Task.sleep(for: $0) },
                  geocode: { await Self.city(of: $0) })
    }

    init(manager: any LocationManaging, sleep: @escaping Sleep, geocode: @escaping Geocode) {
        self.manager = manager
        self.sleep = sleep
        self.geocode = geocode
        manager.onAuthorizationChange = { [weak self] status in
            self?.finishPermission(Self.admits(status))
        }
        manager.onLocation = { [weak self] location in self?.finishFix(location) }
    }

    /// What counts as "may read the location". macOS has no separate "when
    /// in use" status: the grant we ask for comes back as `.authorizedAlways`
    /// (`.authorized` is the same raw value).
    nonisolated static func admits(_ status: CLAuthorizationStatus) -> Bool {
        status == .authorizedAlways
    }

    package nonisolated func current(prompting: Bool) async -> UserLocation? {
        await resolve(prompting: prompting)
    }

    private func resolve(prompting: Bool) async -> UserLocation? {
        let status = manager.authorizationStatus
        if !Self.admits(status) {
            guard status == .notDetermined, prompting else { return nil }
            guard await askPermission() else {
                Log.app("location: permission not granted")
                return nil
            }
        }
        guard let location = await oneFix() else {
            Log.app("location: no fix")
            return nil
        }
        let city = await named(location)
        Log.app(city == nil ? "location: could not name the city" : "location: city resolved")
        return city
    }

    private func askPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            // A second asker must not strand the first: it is told no.
            finishPermission(false)
            permission = continuation
            manager.requestPermission()
            permissionTimer = timer(Self.permissionWait) { $0.finishPermission(false) }
        }
    }

    private func oneFix() async -> CLLocation? {
        await withCheckedContinuation { continuation in
            finishFix(nil)
            fix = continuation
            manager.requestLocation()
            fixTimer = timer(Self.fixWait) { $0.finishFix(nil) }
        }
    }

    private func timer(_ wait: Duration, _ expire: @escaping @MainActor (CoreLocationCityLocator) -> Void) -> Task<Void, Never> {
        let sleep = self.sleep
        return Task { [weak self] in
            do {
                try await sleep(wait)
            } catch {
                return
            }
            // Woken just as the answer arrived and cancelled it: a stale timer
            // must not resolve the next lookup's continuation.
            guard !Task.isCancelled, let self else { return }
            expire(self)
        }
    }

    private func finishPermission(_ granted: Bool) {
        permissionTimer?.cancel()
        permissionTimer = nil
        permission?.resume(returning: granted)
        permission = nil
    }

    private func finishFix(_ location: CLLocation?) {
        fixTimer?.cancel()
        fixTimer = nil
        fix?.resume(returning: location)
        fix = nil
    }

    /// The name lookup is a network call: it gets its own deadline, and the
    /// deadline is a race, not a cancellation the lookup may ignore — a
    /// stalled one cannot hold a `find_places` turn open, and whatever it
    /// answers after the deadline is dropped.
    private func named(_ location: CLLocation) async -> UserLocation? {
        let geocode = self.geocode
        let sleep = self.sleep
        return await withCheckedContinuation { (continuation: CheckedContinuation<UserLocation?, Never>) in
            let once = OneShot(continuation)
            let work = Task { once.finish(await geocode(location)) }
            let deadline = Task {
                do {
                    try await sleep(Self.geocodeWait)
                } catch {
                    return
                }
                if once.finish(nil) {
                    Log.app("location: geocode timed out")
                    work.cancel()
                }
            }
            once.attach(deadline)
        }
    }

    /// Resumes its continuation at most once: the first of the answer and the
    /// deadline wins, the other is discarded.
    private final class OneShot: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<UserLocation?, Never>?
        private var deadline: Task<Void, Never>?
        private var done = false
        init(_ continuation: CheckedContinuation<UserLocation?, Never>) { self.continuation = continuation }

        /// The deadline's timer is released as soon as the answer wins.
        func attach(_ timer: Task<Void, Never>) {
            let late = lock.withLock { () -> Bool in
                if !done { deadline = timer }
                return done
            }
            if late { timer.cancel() }
        }

        @discardableResult
        func finish(_ value: UserLocation?) -> Bool {
            let (taken, timer) = lock.withLock { () -> (CheckedContinuation<UserLocation?, Never>?, Task<Void, Never>?) in
                defer { continuation = nil; deadline = nil; done = true }
                return (continuation, deadline)
            }
            timer?.cancel()
            taken?.resume(returning: value)
            return taken != nil
        }
    }

    /// MapKit's request is not Sendable; it is only ever touched to cancel it.
    private final class GeocodeRequest: @unchecked Sendable {
        let request: MKReverseGeocodingRequest
        init(_ request: MKReverseGeocodingRequest) { self.request = request }
    }

    private nonisolated static func city(of location: CLLocation) async -> UserLocation? {
        guard let made = MKReverseGeocodingRequest(location: location) else { return nil }
        let geocode = GeocodeRequest(made)
        do {
            let items = try await withTaskCancellationHandler {
                try await geocode.request.mapItems
            } onCancel: {
                geocode.request.cancel()
            }
            guard let names = items.first?.addressRepresentations else { return nil }
            return UserLocation(city: names.cityName ?? "", country: names.regionName)
        } catch {
            // The kind of failure, never the place it was about.
            Log.app("location: geocode failed (\(type(of: error)))")
            return nil
        }
    }
}
