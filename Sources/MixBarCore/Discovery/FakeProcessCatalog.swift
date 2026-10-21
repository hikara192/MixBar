import Foundation
import CoreAudio

/// Static fake catalog for the walking skeleton: three apps producing audio
/// plus one paused player that must still be listed.
public final class FakeProcessCatalog: ProcessCataloging, @unchecked Sendable {
    public init() {}

    public func currentApps() -> [DiscoveredApp] {
        [
            DiscoveredApp(
                identity: AppIdentity(canonicalBundleID: "com.spotify.client"),
                displayName: "Spotify",
                processes: [
                    DiscoveredProcess(objectID: 1001, pid: 501, bundleID: "com.spotify.client", isRunningOutput: true),
                ]),
            DiscoveredApp(
                identity: AppIdentity(canonicalBundleID: "us.zoom.xos"),
                displayName: "Zoom",
                processes: [
                    DiscoveredProcess(objectID: 1002, pid: 502, bundleID: "us.zoom.xos", isRunningOutput: true),
                    DiscoveredProcess(objectID: 1003, pid: 503, bundleID: "us.zoom.xos", isRunningOutput: true),
                ]),
            DiscoveredApp(
                identity: AppIdentity(canonicalBundleID: "com.google.Chrome"),
                displayName: "Google Chrome",
                processes: [
                    DiscoveredProcess(objectID: 1004, pid: 504, bundleID: "com.google.Chrome", isRunningOutput: true),
                    DiscoveredProcess(objectID: 1005, pid: 505, bundleID: "com.google.Chrome.helper", isRunningOutput: true),
                ]),
            // Silent app: has an audio client but is not outputting right now.
            DiscoveredApp(
                identity: AppIdentity(canonicalBundleID: "com.apple.Music"),
                displayName: "Music",
                processes: [
                    DiscoveredProcess(objectID: 1006, pid: 506, bundleID: "com.apple.Music", isRunningOutput: false),
                ],
                isAudible: false),
        ]
    }
}
