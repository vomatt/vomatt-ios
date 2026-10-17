// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VomattKit",
    defaultLocalization: "en",
    // macOS only so `swift test` runs on the host without a simulator
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "VomattCore", targets: ["VomattCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.7.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.0.0"),
    ],
    targets: [
        // Generated at build time from openapi.json (synced from vomatt-web's api-docs.json)
        .target(
            name: "VomattAPI",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            ],
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator"),
            ]
        ),
        // Domain models, the API service, auth and everything else the app uses that isn't UI
        .target(
            name: "VomattCore",
            dependencies: [
                "VomattAPI",
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            ]
        ),
        .testTarget(
            name: "VomattCoreTests",
            dependencies: ["VomattCore", "VomattAPI"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
