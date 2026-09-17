import AVFoundation
import Foundation

@MainActor final class RestMusic: NSObject, @preconcurrency AVAudioPlayerDelegate {
    struct Track: Equatable {
        let file: String
        let title: String
    }

    static let tracks = [
        Track(file: "clear-air", title: "Clear Air"),
        Track(file: "peppers-theme", title: "Pepper’s Theme"),
        Track(file: "meditation-impromptu-01", title: "Meditation Impromptu 01"),
        Track(file: "avec-soin", title: "Avec Soin")
    ]

    private let defaults: UserDefaults
    private var queue: [Track] = []
    private var lastFile: String?
    private(set) var player: AVAudioPlayer?
    private(set) var currentTrack: Track?
    private(set) var active = false
    private(set) var suspended = false
    private(set) var fadingOut = false
    private var remaining: TimeInterval = 0

    var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: "musicEnabled")
            if !enabled { stopPlayer() }
            else if active && !suspended && !fadingOut { playNext() }
        }
    }
    var volume: Float {
        didSet {
            defaults.set(volume, forKey: "musicVolume")
            if !fadingOut { player?.setVolume(volume, fadeDuration: 0.3) }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["musicEnabled": true, "musicVolume": 0.25])
        enabled = defaults.bool(forKey: "musicEnabled")
        volume = min(1, max(0, defaults.float(forKey: "musicVolume")))
        lastFile = defaults.string(forKey: "lastMusicFile")
        super.init()
    }

    static func resource(_ name: String, extension ext: String) -> URL? {
        // Installed app resources take precedence; Bundle.module supports swift run.
        if Bundle.main.bundleURL.pathExtension == "app" {
            return Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Music")
        }
        return Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Music")
    }

    func start(remaining: TimeInterval) {
        stop()
        active = true
        self.remaining = remaining
        if enabled && remaining > 0 { playNext() }
    }

    func update(remaining: TimeInterval, suspended: Bool) {
        guard active else { return }
        self.remaining = remaining
        guard remaining > 0 else { stop(); return }
        if suspended != self.suspended {
            self.suspended = suspended
            if suspended {
                player?.pause()
            } else if enabled {
                if let player {
                    player.volume = 0
                    player.play()
                    if !fadingOut { player.setVolume(volume, fadeDuration: min(1, remaining)) }
                } else if !fadingOut { playNext() }
            }
        }
        if remaining <= 2 && !fadingOut {
            fadingOut = true
            player?.setVolume(0, fadeDuration: remaining)
        }
    }

    func stop() {
        active = false
        suspended = false
        fadingOut = false
        remaining = 0
        stopPlayer()
    }

    private func stopPlayer() {
        player?.delegate = nil
        player?.stop()
        player = nil
        currentTrack = nil
    }

    private func playNext() {
        guard active && enabled && !suspended && !fadingOut else { return }
        stopPlayer()
        // A shuffled bag plays all tracks before repeating, including across breaks.
        for _ in 0..<Self.tracks.count {
            if queue.isEmpty {
                queue = Self.tracks.shuffled()
                if queue.first?.file == lastFile, queue.count > 1 { queue.swapAt(0, 1) }
            }
            let track = queue.removeFirst()
            guard let url = Self.resource(track.file, extension: "m4a"),
                  let audio = try? AVAudioPlayer(contentsOf: url) else { continue }
            audio.delegate = self
            audio.volume = 0
            guard audio.prepareToPlay(), audio.play() else { continue }
            player = audio
            currentTrack = track
            lastFile = track.file
            defaults.set(track.file, forKey: "lastMusicFile")
            audio.setVolume(volume, fadeDuration: min(3, max(0, remaining - 2)))
            return
        }
        // Missing or unreadable music must never prevent a break from completing.
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === self.player else { return }
        if active && !suspended && !fadingOut { playNext() }
        else { stopPlayer() }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        guard player === self.player else { return }
        stopPlayer()
    }
}
