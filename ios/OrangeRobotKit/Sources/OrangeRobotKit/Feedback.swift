#if canImport(UIKit)
import UIKit
import AudioToolbox

/// Moments in the apps that can give a little haptic tap and a short sound.
public enum FeedbackCue: String, CaseIterable, Sendable {
    case buy, sell, news, finished, win, bust, tap
    /// Haptic-only cues for interface changes and game feel.
    case select, start, pause, resume, wake, milestone, near, danger, swing
}

/// Haptics and sound, each with its own on/off switch (both default on).
/// Sounds are short synthesised tones bundled with the package, played as
/// system sounds, so they respect the silent switch and never interrupt music
/// or the audiobook prologue.
public enum Feedback {
    public static let hapticsKey = "fx_haptics"
    public static let soundKey = "fx_sound"

    public static var hapticsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: hapticsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: hapticsKey) }
    }
    public static var soundEnabled: Bool {
        get { UserDefaults.standard.object(forKey: soundKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: soundKey) }
    }

    private static var ids: [FeedbackCue: SystemSoundID] = [:]
    private static var silent: Set<FeedbackCue> = []

    private static func later(_ seconds: Double, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    public static func play(_ cue: FeedbackCue) {
        if hapticsEnabled { haptic(for: cue) }
        if soundEnabled { sound(for: cue) }
    }

    private static func haptic(for cue: FeedbackCue) {
        switch cue {
        case .buy: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .sell: UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .tap: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .news: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .finished, .win: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .bust: UINotificationFeedbackGenerator().notificationOccurred(.error)

        case .select: UISelectionFeedbackGenerator().selectionChanged()
        case .start: UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .pause: UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.9)
        case .resume: UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6)
        case .wake:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            later(0.12) { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        case .milestone:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            later(0.1) { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
            later(0.2) { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
        case .near: UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
        case .danger:   // a heartbeat
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            later(0.18) { UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 0.7) }
        case .swing: UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.8)
        }
    }

    private static func sound(for cue: FeedbackCue) {
        if silent.contains(cue) { return }
        if ids[cue] == nil {
            guard let url = Bundle.module.url(forResource: "fx_\(cue.rawValue)", withExtension: "wav",
                                              subdirectory: nil) ?? Bundle.module.url(forResource: "fx_\(cue.rawValue)", withExtension: "wav", subdirectory: "Sounds")
            else { silent.insert(cue); return }     // haptic-only cue: no sound file
            var id: SystemSoundID = 0
            AudioServicesCreateSystemSoundID(url as CFURL, &id)
            ids[cue] = id
        }
        if let id = ids[cue] { AudioServicesPlaySystemSound(id) }
    }
}
#endif
