import SwiftUI
import AVFoundation
import MediaPlayer
import Observation

@MainActor @Observable
final class ProloguePlayer {
    private(set) var isPlaying = false
    private(set) var current: Double = 0
    private(set) var duration: Double = 0
    private(set) var failed = false
    var isScrubbing = false

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var commandsInstalled = false
    private var reportedPlay = false

    private static let title = "The Orange Robot — Prologue"

    func prepare() {
        guard player == nil else { return }
        guard let url = Bundle.main.url(forResource: "prologue", withExtension: "m4a") else {
            failed = true
            return
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        player = p

        Task {
            if let d = try? await item.asset.load(.duration), d.isNumeric { duration = d.seconds }
            updateNowPlaying()
        }
        timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
                                                 queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, !self.isScrubbing else { return }
                self.current = t.seconds
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isPlaying = false
                Activity.track(.prologueComplete)
                self.seek(to: 0)
                self.updateNowPlaying()
            }
        }
        installRemoteCommands()
    }

    func toggle() { isPlaying ? pause() : play() }

    func play() {
        prepare()
        guard let player else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        isPlaying = true
        if !reportedPlay { reportedPlay = true; Activity.track(.prologuePlay) }
        updateNowPlaying()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func seek(to seconds: Double) {
        let t = min(max(0, seconds), max(duration, 0))
        current = t
        player?.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        updateNowPlaying()
    }

    func skip(_ delta: Double) { seek(to: current + delta) }

    /// Stop and release playback (used when the sheet closes).
    func stop() {
        pause()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player = nil
        current = 0
        reportedPlay = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Lock screen / Control Center

    private func updateNowPlaying() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: Self.title,
            MPMediaItemPropertyArtist: "V.J. Alden",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: current,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let img = UIImage(named: "BookCover") {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func installRemoteCommands() {
        guard !commandsInstalled else { return }
        commandsInstalled = true
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.play() }; return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }; return .success
        }
        c.skipForwardCommand.preferredIntervals = [15]
        c.skipForwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.skip(15) }; return .success
        }
        c.skipBackwardCommand.preferredIntervals = [15]
        c.skipBackwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.skip(-15) }; return .success
        }
        c.changePlaybackPositionCommand.addTarget { [weak self] e in
            guard let e = e as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            MainActor.assumeIsolated { self?.seek(to: e.positionTime) }
            return .success
        }
    }
}

struct PrologueView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var player = ProloguePlayer()

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Spacer(minLength: 8)
                Image("BookCover")
                    .resizable().scaledToFit().frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: Theme.orange.opacity(0.45), radius: 28)
                VStack(spacing: 4) {
                    Text("The Prologue").font(.system(size: 20, weight: .heavy)).foregroundStyle(Theme.text)
                    Text("THE ORANGE ROBOT · V.J. ALDEN")
                        .font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundStyle(Theme.dim)
                }

                if player.failed {
                    Text("The audio file is missing from this build.")
                        .font(.system(size: 13)).foregroundStyle(Theme.red)
                } else {
                    scrubber
                    controls
                }

                Link(destination: Theme.bookURL) {
                    Text("HEAR THE FULL AUDIOBOOK →")
                        .font(.system(size: 13, weight: .black)).tracking(0.5)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.orange, lineWidth: 1.5))
                        .foregroundStyle(Theme.orange)
                }
                .simultaneousGesture(TapGesture().onEnded { Activity.track(.audiobookLinkTap) })
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 24)
            .background(Theme.bg)
            .navigationTitle("🎧 Listen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .onAppear { player.prepare() }
        .onDisappear { player.stop() }
    }

    private var scrubber: some View {
        VStack(spacing: 4) {
            Slider(value: Binding(get: { player.current },
                                  set: { player.seek(to: $0) }),
                   in: 0...max(player.duration, 1),
                   onEditingChanged: { player.isScrubbing = $0 })
                .tint(Theme.orange)
            HStack {
                Text(Self.time(player.current))
                Spacer()
                Text("-" + Self.time(max(0, player.duration - player.current)))
            }
            .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.dim)
        }
    }

    private var controls: some View {
        HStack(spacing: 38) {
            Button { player.skip(-15) } label: {
                Image(systemName: "gobackward.15").font(.system(size: 28))
            }
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 68)).foregroundStyle(Theme.orange)
            }
            Button { player.skip(15) } label: {
                Image(systemName: "goforward.15").font(.system(size: 28))
            }
        }
        .foregroundStyle(Theme.text)
    }

    private static func time(_ s: Double) -> String {
        let t = Int(max(0, s).rounded())
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
