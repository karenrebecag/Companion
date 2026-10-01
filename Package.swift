// swift-tools-version: 6.2
import PackageDescription

// Cuatro targets = cuatro capas. Las dependencias entre targets SON la
// arquitectura: si Core intentara importar UI, no compila.
let package = Package(
    name: "Companion",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "companion", targets: ["CompanionApp"]),
    ],
    targets: [
        // Dominio puro: máquina de estados, codecs de protocolo, parsing.
        // Sin red, sin audio, sin UI. Todo testeable sin mocks de frameworks.
        .target(name: "CompanionCore"),

        // Adaptadores al mundo real: red, audio, subprocesos, Keychain.
        // Implementan los puertos (protocolos) que Core define.
        // Skills/<name>/SKILL.md: the system skills (Wave 11a), copied as-is
        // and seeded onto disk at launch so the user can open them.
        // Diagram/: the vendored mermaid.js the isolated web view draws with
        // (16m-5b); a file, not a SwiftPM dependency. VENDOR.md pins it.
        .target(
            name: "CompanionServices",
            dependencies: ["CompanionCore"],
            resources: [.copy("Skills"), .copy("Diagram")]
        ),

        // SwiftUI + tokens de diseño. MainActor por default: el compilador
        // garantiza que nada muta estado observable fuera del main thread.
        .target(
            name: "CompanionUI",
            dependencies: ["CompanionCore"],
            resources: [.copy("Fonts"), .copy("Mascot")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),

        // Raíz de composición: crea adaptadores, los inyecta y arranca la app.
        .executableTarget(
            name: "CompanionApp",
            dependencies: ["CompanionCore", "CompanionServices", "CompanionUI"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),

        // Test support targets: regular targets (never test targets) so several
        // test targets can share them. No @testable, no swiftSettings; what they
        // expose is `package`. scripts/check-test-layers.sh enforces both.
        .target(name: "CompanionTestKit", path: "Tests/CompanionTestKit"),

        .target(
            name: "CompanionCoreTestSupport",
            dependencies: ["CompanionCore", "CompanionTestKit"],
            path: "Tests/CompanionCoreTestSupport"
        ),

        .target(
            name: "CompanionServicesTestSupport",
            dependencies: [
                "CompanionServices", "CompanionCoreTestSupport", "CompanionTestKit",
            ],
            path: "Tests/CompanionServicesTestSupport"
        ),

        // No .defaultIsolation here, unlike CompanionUI: helpers state their own
        // @MainActor, so test targets that never see UI types can share them.
        .target(
            name: "CompanionUITestSupport",
            dependencies: [
                "CompanionUI", "CompanionCoreTestSupport", "CompanionTestKit",
            ],
            path: "Tests/CompanionUITestSupport"
        ),

        .testTarget(
            name: "CompanionTests",
            dependencies: [
                "CompanionCore", "CompanionServices", "CompanionUI",
                "CompanionTestKit", "CompanionCoreTestSupport",
                "CompanionServicesTestSupport", "CompanionUITestSupport",
            ],
            path: "Tests/CompanionTests"
        ),
    ]
)
