#if canImport(UIKit)
import UIKit
import AudioToolbox

/// Moments in the apps that can give a little haptic tap and a short sound.
public enum FeedbackCue: String, CaseIterable, Sendable {
    case buy, sell, news, finished, win, bust, tap
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
        }
    }

    private static func sound(for cue: FeedbackCue) {
        if ids[cue] == nil {
            guard let url = Bundle.module.url(forResource: "fx_\(cue.rawValue)", withExtension: "wav",
                                              subdirectory: nil) ?? Bundle.module.url(forResource: "fx_\(cue.rawValue)", withExtension: "wav", subdirectory: "Sounds")
            else { return }
            var id: SystemSoundID = 0
            AudioServicesCreateSystemSoundID(url as CFURL, &id)
            ids[cue] = id
        }
        if let id = ids[cue] { AudioServicesPlaySystemSound(id) }
    }
}
#endif
