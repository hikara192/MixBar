// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MixBar",
    platforms: [.macOS(.v14)],
    targets: [
        // Vendored C11 atomics shim: zero dependencies, native RT-grade primitives (ADR-004).
        .target(name: "CAtomic"),
        .target(name: "MixBarCore", dependencies: ["CAtomic"]),
        .executableTarget(name: "MixBarApp", dependencies: ["MixBarCore"]),
        .testTarget(name: "MixBarTests", dependencies: ["MixBarCore", "CAtomic"]),
    ]
)
