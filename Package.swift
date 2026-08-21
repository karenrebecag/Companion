// swift-tools-version: 6.2
import PackageDescription

// Cuatro targets = cuatro capas. Las dependencias entre targets SON la
// arquitectura: si Core intentara importar UI, no compila.
let package = Package(
    name: "Companion",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "companion", targets: ["CompanionApp"]),
        .library(name: "CompanionCore", targets: ["CompanionCore"]),
    ],
    targets: [
        // Dominio puro: máquina de estados, codecs de protocolo, parsing.
        // Sin red, sin audio, sin UI. Todo testeable sin mocks de frameworks.
        .target(name: "CompanionCore"),

        // Adaptadores al mundo real: red, audio, subprocesos, Keychain.
        // Implementan los puertos (protocolos) que Core define.
        .target(name: "CompanionServices", dependencies: ["CompanionCore"]),

        // SwiftUI + tokens de diseño. MainActor por default: el compilador
        // garantiza que nada muta estado observable fuera del main thread.
        // Rive ships as a prebuilt xcframework: the mascot has a state
        // machine and pointer listeners the app does not have to reimplement.
        // dSYMs stripped — 15 MB in, 40 MB of debug symbols left out.
        .binaryTarget(
            name: "RiveRuntime",
            path: "vendor/RiveRuntime.xcframework"
        ),

        .target(
            name: "CompanionUI",
            dependencies: ["CompanionCore", "RiveRuntime"],
            resources: [.copy("Fonts"), .copy("Mascot")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),

        // Raíz de composición: crea adaptadores, los inyecta y arranca la app.
        .executableTarget(
            name: "CompanionApp",
            dependencies: ["CompanionCore", "CompanionServices", "CompanionUI"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),

        .testTarget(
            name: "CompanionTests",
            dependencies: ["CompanionCore", "CompanionServices", "CompanionUI"],
            path: "Tests/CompanionTests"
        ),
    ]
)
