// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexQuota",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "CodexQuotaCore", targets: ["CodexQuotaCore"]),
        .executable(name: "CodexQuota", targets: ["CodexQuota"]),
    ],
    targets: [
        .target(name: "CodexQuotaCore"),
        .executableTarget(
            name: "CodexQuota",
            dependencies: ["CodexQuotaCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "CodexQuotaCoreTests",
            dependencies: ["CodexQuotaCore"]
        ),
    ]
)
