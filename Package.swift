// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Aura",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Aura", targets: ["Aura"])],
    targets: [
        .target(name: "AuraCore"),
        .target(name: "CMPV", linkerSettings: [.linkedFramework("OpenGL")]),
        .executableTarget(name: "Aura", dependencies: ["AuraCore", "CMPV"],
                          resources: [.copy("Resources")]),
        .executableTarget(name: "AuraCoreChecks", dependencies: ["AuraCore"], path: "Tests/AuraCoreTests")
    ],
    swiftLanguageVersions: [.v5]
)
