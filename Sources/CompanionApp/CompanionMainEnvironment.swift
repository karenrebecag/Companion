import AppKit
import CompanionCore
import CompanionServices
import CompanionUI
import CoreGraphics
import SwiftUI

/// What launch needs before any provider or session exists: logging, the
/// keychain/network primitives, memory+skills, and the on-disk layout. Split
/// out of `applicationDidFinishLaunching` when CompanionMain crossed the
/// 400-line gate.
struct LaunchEnvironment {
    let home: URL
    let support: URL
    let secrets: CachingSecretStore
    /// The same Keychain instance behind `secrets`: two would each cache the
    /// one bundle item and overwrite each other's writes.
    let hostSecrets: any HostSecretStore
    let transport: URLSessionChatTransport
    let probe: LiveCapabilityProbe
    let memoryStore: FileMemoryStore
    let skillsLocation: SkillsLocation
    let skillStore: SkillStore
    let configProvider: StoredConfigProvider
    let config: Config
}

/// Verbatim from the top of the old `applicationDidFinishLaunching`.
func makeLaunchEnvironment() -> LaunchEnvironment {
    let home = FileManager.default.homeDirectoryForCurrentUser
    // The bundle around the binary decides which app this is; the log
    // follows it so two builds never interleave their turns.
    let identity = ProductIdentity.of(
        bundleID: Bundle.main.bundleIdentifier)
    Log.configure(
        fileURL: home.appendingPathComponent(
            "Library/Logs/\(identity.logFileName)"))
    Fonts.register()
    // Before any request: older builds cached keys and request bodies.
    LegacyURLCachePurge.runAtLaunch(bundleID: Bundle.main.bundleIdentifier)

    let support = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Companion/conversations")
    do {
        try FileManager.default.createDirectory(
            at: support, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
    } catch {
        // Log without error details to avoid exposing system paths/permissions.
        Log.app("could not create conversations dir")
    }

    // Envuelto: el bucle de routing pide la misma clave dos veces por
    // proveedor y la voz otra vez al abrir sesion. Sin cache eso son
    // varias lecturas del llavero por mensaje, y cuando el ACL del item no
    // reconoce a la app, cada lectura es un dialogo de contrasena.
    let keychain = KeychainSecretStore()
    let secrets = CachingSecretStore(keychain)
    let transport = URLSessionChatTransport()
    let probe = LiveCapabilityProbe(transport: transport)
    // No default reach. Handing over the whole home folder on first launch
    // was a security decision taken by omission: nobody chose it and
    // nobody was asked. Without a folder the specialist simply has none,
    // and the question arrives when reach is actually needed instead of
    // as friction at startup.
    // 9j-2: memory lives in plain markdown the user can open and edit.
    // The profile already written in Settings seeds the core on first run.
    let memoryStore = FileMemoryStore()
    memoryStore.ensureCore(seed: [UserProfile.about, UserProfile.instructions]
        .filter { !$0.isEmpty }.joined(separator: "\n\n"))
    // Wave 11a: skills and knowledge next to memory. The system skills
    // are seeded from the bundle at every launch; a bundle that does not
    // load is logged and the app runs without a catalog, promising none.
    let skillsLocation = SkillsLocation.standard()
    let bundledSkills: [BundledSkill]
    do {
        bundledSkills = try BundledSkills.load()
    } catch {
        Log.app("skills: bundle not loaded (\(error)); no system skills this launch")
        bundledSkills = []
    }
    let skillStore = SkillStore(location: skillsLocation, bundled: bundledSkills)
    let seeded = skillStore.seed()
    if !seeded.isEmpty { Log.app("skills: seeded \(seeded.joined(separator: ", "))") }
    let configProvider = StoredConfigProvider(
        workdir: nil, memory: memoryStore, skills: skillStore, location: skillsLocation,
        hostSecrets: keychain)
    let config = configProvider.current

    return LaunchEnvironment(
        home: home, support: support, secrets: secrets, hostSecrets: keychain, transport: transport,
        probe: probe, memoryStore: memoryStore, skillsLocation: skillsLocation,
        skillStore: skillStore, configProvider: configProvider, config: config)
}
