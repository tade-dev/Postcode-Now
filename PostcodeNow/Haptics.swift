import PostcodeNowCore
import UIKit

/// Fires each declared cue once as the reveal's clock crosses it.
///
/// A reference type rather than view state on purpose: the canvas is
/// re-evaluated many times per frame and must not re-fire what it already
/// played. `reset()` is what makes a retry start clean instead of replaying
/// or swallowing cues.
final class HapticScheduler {
    private var firedThrough = -1
    private var generators: [HapticStyle: UIImpactFeedbackGenerator] = [:]

    func reset() {
        firedThrough = -1
        prepare()
    }

    func prepare() {
        for style in [HapticStyle.rigid, .soft, .light] where generators[style] == nil {
            let generator = UIImpactFeedbackGenerator(style: style.uiStyle)
            generator.prepare()
            generators[style] = generator
        }
    }

    func advance(to elapsed: Double, cues: [HapticCue]) {
        guard !cues.isEmpty else { return }
        var index = firedThrough + 1
        while index < cues.count, cues[index].time <= elapsed {
            fire(cues[index].style)
            index += 1
        }
        firedThrough = index - 1
    }

    /// Reduce Motion lands the reveal settled in one step, so there is no
    /// clock for `advance` to walk. Haptics are not motion and still fire:
    /// one confirmation impact as the code lands, never the whole schedule
    /// in a single burst.
    func confirmSettled() {
        fire(.rigid)
    }

    private func fire(_ style: HapticStyle) {
        let generator = generators[style] ?? UIImpactFeedbackGenerator(style: style.uiStyle)
        generators[style] = generator
        DispatchQueue.main.async {
            generator.impactOccurred()
            generator.prepare()
        }
    }
}

private extension HapticStyle {
    var uiStyle: UIImpactFeedbackGenerator.FeedbackStyle {
        switch self {
        case .rigid: return .rigid
        case .soft: return .soft
        case .light: return .light
        }
    }
}
