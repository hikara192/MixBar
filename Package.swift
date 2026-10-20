// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MixBar",
    platforms: [.macOS(.v14)],
    targets: [
        // Vendored C11 atomics shim: zero dependencies, native RT-grade primitives (ADR-004).
        .target(name: "CAtomic"),
        .target(name: "MixBarCore", dependencies: ["CAtomic"]),
        // UI strings, language resolution and the observable language store.
        // Kept separate so tests can assert that every key exists in both languages.
        .target(name: "MixBarLocalization"),
        .executableTarget(name: "MixBarApp", dependencies: ["MixBarCore", "MixBarLocalization"]),
        // Spike S1 (throwaway): real tap + aggregate + IOProc diagnostics.
        .executableTarget(name: "MixBarSpike", dependencies: ["CAtomic"]),
        .testTarget(name: "MixBarTests", dependencies: ["MixBarCore", "MixBarLocalization", "CAtomic"]),
    ]
)
