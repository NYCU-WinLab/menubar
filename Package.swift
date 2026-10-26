// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WinLab",
    defaultLocalization: "zh-Hant",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "WinLab", targets: ["WinLab"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        // The portal API: generated types from contract/portal.json, the HTTP
        // client and the change stream. No UI, so it is tested on its own.
        .target(name: "PortalKit"),
        .executableTarget(
            name: "WinLab",
            dependencies: ["PortalKit", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [
                // Sparkle.framework sits in Contents/Frameworks of the bundle.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        // Turns contract/portal.json into Sources/PortalKit/Generated.swift.
        .executableTarget(name: "ContractGen"),
        .testTarget(name: "PortalKitTests", dependencies: ["PortalKit"]),
    ]
)
