import Foundation

@main
enum Version65AudioPolicySelfTest {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    static func main() async {
        await MainActor.run {
            UserDefaults.standard.removeObject(forKey: "PulseDock.mediaNetworkMode")
            let service = AmbientSoundService()
            require(service.playbackState == .idle && !service.isPlaying, "audio must start idle and silent")
            require(service.selectedItem == nil && service.stopAt == nil, "audio must not restore a prior stream or timer")
            require(service.tracks.count == 24, "the reviewed CC0 ambient catalog must contain four complete six-card pages")
            require(Set(service.tracks.map(\.id)).count == service.tracks.count, "ambient IDs must be unique")
            require(Set(service.tracks.map(\.streamURL)).count == service.tracks.count, "ambient streams must not accidentally duplicate")
            require(Set(service.tracks.map(\.sourceID)).count == service.tracks.count, "provider source IDs must be unique")
            require(service.tracks.allSatisfy {
                $0.streamURL.scheme == "https" && $0.streamURL.host == "cdn.freesound.org" &&
                $0.sourcePage.scheme == "https" && $0.sourcePage.host == "freesound.org" &&
                $0.license == "CC0" && $0.licenseURL.absoluteString == "https://creativecommons.org/publicdomain/zero/1.0/" &&
                $0.sourceID.hasPrefix("freesound:") && !$0.tags.isEmpty && $0.duration > 0 &&
                $0.lastVerified == "2026-08-25"
            }, "ambient tracks need complete HTTPS CC0 provenance and audit metadata")
            require(Set(service.tracks.map(\.sceneStyle)).count >= 12, "ambient catalogue needs distinct reviewed scene styles, not one generic waveform")
            require(service.tracks.allSatisfy { AmbientTrack.sceneStyle(for: $0.id) == $0.sceneStyle }, "scene visual style must come from explicit catalogue metadata")
            require(service.ambientCategories.count >= 8, "ambient discovery needs multiple useful categories")
            require(service.ambientCategories.allSatisfy { $0.trackIDs.count >= 2 }, "each visible ambient category must offer a real choice")
            let categorizedIDs = service.ambientCategories.reduce(into: Set<String>()) { $0.formUnion($1.trackIDs) }
            require(categorizedIDs == Set(service.tracks.map(\.id)), "every ambient track must appear in at least one category")
            let memberships = service.tracks.map { track in service.ambientCategories.filter { $0.trackIDs.contains(track.id) }.count }
            require(memberships.contains(where: { $0 > 1 }), "categories must support one recording in multiple discovery contexts")

            let unsafe = MediaStreamItem(
                id: "unsafe", kind: .radio, title: "Unsafe", subtitle: "test", symbol: "radio",
                streamURL: URL(string: "http://127.0.0.1/audio.mp3")!,
                sourcePage: URL(string: "https://example.com")!, provider: "test", license: "test",
                country: nil, language: nil, codec: "MP3", bitrateKbps: nil, isLive: true
            )
            service.play(unsafe)
            require(service.playbackState == .failed && !service.isPlaying && service.selectedItem == nil, "HTTP audio must fail before a player is created")
            service.stop(); service.stop()
            require(service.playbackState == .idle && service.selectedItem == nil, "stop must be idempotent")
            service.volume = 0.46
            service.toggleMute()
            require(service.volume == 0, "mute must use a real zero volume value")
            service.toggleMute()
            require(service.volume >= 0.45, "unmute must restore the previous audible volume")
            require(DirectAudioRelay.isSafePublicHTTPS(URL(string: "https://stream.example.com/live.mp3")), "smart direct must allow public HTTPS audio")
            require(!DirectAudioRelay.isSafePublicHTTPS(URL(string: "https://127.0.0.1/live.mp3")), "smart direct must reject loopback SSRF")
            require(!DirectAudioRelay.isSafePublicHTTPS(URL(string: "https://192.168.1.2/live.mp3")), "smart direct must reject private network SSRF")
        }
        print("PulseDock 6.9 audio policy self-test passed")
    }
}
