// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PurePDF",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "PurePDFCore",
            targets: ["PurePDFCore"]
        )
    ],
    targets: [
        .target(
            name: "PurePDFCore",
            path: "PurePDF"
        )
    ]
)
