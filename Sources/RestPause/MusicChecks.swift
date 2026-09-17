import AVFoundation
import Foundation
import Darwin

@MainActor func runMusicChecks() async {
    let suite = "local.restpause.music-check.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let music = RestMusic(defaults: defaults)
    var failures = 0
    func check(_ label: String, _ passed: Bool) {
        print("MUSIC \(label): \(passed ? "PASS" : "FAIL")")
        if !passed { failures += 1 }
    }
    check("enabled by default at 25 percent", music.enabled && music.volume == 0.25)
    music.volume = 0 // Exercise real playback without changing the user's output volume.
    for track in RestMusic.tracks {
        let audio = RestMusic.resource(track.file, extension: "m4a").flatMap { try? AVAudioPlayer(contentsOf: $0) }
        check("bundled audio decodes: \(track.title)", (audio?.duration ?? 0) > 120 && audio?.prepareToPlay() == true)
    }
    check("bundled attribution", RestMusic.resource("Credits", extension: "txt") != nil)
    music.enabled = false
    music.start(remaining: 300)
    check("disabled music stays silent", music.player == nil)
    music.enabled = true
    check("enabling starts one player", music.player?.isPlaying == true)
    music.stop()
    var previous: String?
    var firstCycle = Set<String>()
    var noRepeats = true
    for index in 0..<12 {
        music.start(remaining: 300)
        let file = music.currentTrack?.file
        noRepeats = noRepeats && file != nil && file != previous
        // The first enable above consumed one entry from the initial bag.
        if (3..<7).contains(index), let file { firstCycle.insert(file) }
        previous = file
        music.stop()
    }
    check("no consecutive repeats across breaks", noRepeats)
    check("shuffle cycle covers every track", firstCycle.count == RestMusic.tracks.count)
    music.start(remaining: 300)
    let first = music.currentTrack
    music.update(remaining: 290, suspended: true)
    check("lock or sleep pauses playback", music.suspended && music.player?.isPlaying == false)
    music.update(remaining: 280, suspended: false)
    check("resume preserves the track", music.player?.isPlaying == true && music.currentTrack == first)
    if let player = music.player { player.currentTime = player.duration - 0.1 }
    try? await Task.sleep(for: .milliseconds(700))
    check("track completion starts a different track", music.player?.isPlaying == true && music.currentTrack != first)
    music.player?.volume = 0.1
    music.update(remaining: 0.2, suspended: false)
    check("natural ending begins fade", music.fadingOut)
    try? await Task.sleep(for: .milliseconds(350))
    check("fade reaches silence", (music.player?.volume ?? 1) < 0.01)
    music.update(remaining: 0, suspended: false)
    check("rest completion releases player", !music.active && music.player == nil)
    music.start(remaining: 300)
    let oldPlayer = music.player
    music.stop()
    check("emergency stop is immediate", oldPlayer?.isPlaying == false && music.player == nil)
    if let oldPlayer { music.audioPlayerDidFinishPlaying(oldPlayer, successfully: true) }
    check("late completion cannot restart audio", music.player == nil && !music.active)
    music.enabled = false; music.volume = 0.4
    let reloaded = RestMusic(defaults: defaults)
    check("preferences persist", !reloaded.enabled && reloaded.volume == 0.4)
    defaults.removePersistentDomain(forName: suite)
    exit(failures == 0 ? 0 : 1)
}
