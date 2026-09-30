import CompanionCore
import Foundation
import Vision

/// The clip's captures (spec 16i §2): `screencapture -i` into a private
/// temporary folder, and Vision's on-device text recognizer. Nothing leaves
/// the Mac; the caller adopts the file and then discards it here.
package struct ScreenRegionGrabber: RegionGrabbing {
    private let directory: URL
    private let permission: any ScreenRecordingChecking

    package init(directory: URL, permission: any ScreenRecordingChecking = ScreenRecordingPermission()) {
        self.directory = directory.standardizedFileURL
        self.permission = permission
    }

    /// The folder may hold sensitive screen content from a run that never
    /// got to discard it. Called at launch; only ever empties its own folder,
    /// and never follows a link out of it.
    package func purgeLeftovers() {
        let fm = FileManager.default
        do {
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { return }
        } catch {
            return
        }
        do {
            for url in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                try fm.removeItem(at: url)
            }
        } catch {
            Log.app("capture: could not clear the capture folder")
        }
    }

    package func capture() async -> RegionGrab {
        guard permission.isGranted() else {
            permission.request()
            return .needsPermission
        }
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
        } catch {
            Log.app("capture: could not create the capture folder")
            return .failed
        }
        let url = directory.appendingPathComponent(RegionCapture.fileName(id: UUID()))
        let code = await Self.run(arguments: RegionCapture.arguments(to: url.path))
        switch RegionCapture.outcome(exitCode: code, bytesWritten: Self.bytes(at: url)) {
        case .captured:
            return .captured(url)
        case .cancelled:
            discard(url)
            return .cancelled
        case .failed:
            Log.app("capture: screencapture exited \(code)")
            discard(url)
            return .failed
        }
    }

    package func recognizeText(at url: URL) async -> String? {
        await Task.detached(priority: .userInitiated) { Self.recognize(url) }.value
    }

    package func discard(_ url: URL) {
        let target = url.standardizedFileURL
        // Only what this grabber wrote: the caller's own files are not ours to delete.
        guard target.path.hasPrefix(directory.path + "/"),
              FileManager.default.fileExists(atPath: target.path) else { return }
        do {
            try FileManager.default.removeItem(at: target)
        } catch {
            Log.app("capture: could not remove a temporary capture")
        }
    }

    /// The picker waits on the user; cancelling the task closes it.
    private static func run(arguments: [String]) async -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: RegionCapture.executable)
        process.arguments = arguments
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    Log.app("capture: screencapture did not start")
                    continuation.resume(returning: -1)
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    private static func bytes(at url: URL) -> Int? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            return (attrs[.size] as? NSNumber)?.intValue
        } catch {
            return nil
        }
    }

    private static func recognize(_ url: URL) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["es-ES", "en-US", "pt-BR"]
        do {
            try VNImageRequestHandler(url: url).perform([request])
        } catch {
            Log.app("capture: text recognition failed")
            return nil
        }
        let lines = (request.results ?? []).compactMap { observation -> RecognizedLine? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox
            return RecognizedLine(text: text, x: Double(box.origin.x), y: Double(box.origin.y))
        }
        return RecognizedText.join(lines)
    }
}
