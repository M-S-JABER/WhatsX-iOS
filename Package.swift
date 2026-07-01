// swift-tools-version:5.9
import PackageDescription

// WhatsX as a Swift Package so it can be imported on iPad (Swift Playgrounds)
// or in Xcode. The whole app (data + design + all SwiftUI screens) lives in the
// single `WhatsX` library; a host app just renders `WhatsXRoot()`.
//
// The macOS @main lives in Sources/App/WhatsXApp.swift and is EXCLUDED here,
// because a library target cannot contain an application entry point.
let package = Package(
    name: "WhatsX",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(name: "WhatsX", targets: ["WhatsX"])
    ],
    targets: [
        .target(
            name: "WhatsX",
            path: "Sources",
            exclude: ["App/WhatsXApp.swift"]
        )
    ]
)
