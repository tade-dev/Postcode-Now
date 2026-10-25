import PostcodeNowCore
import SwiftUI

/// Every layer the timeline drives, in one view that is never torn down.
/// The ring and the postcode have to share a view identity for the reveal to
/// be continuous — if SwiftUI can remove one and insert the other, the user
/// sees a cut no matter how the timings are tuned.
struct RevealCanvas: View, Animatable {
    var elapsed: Double?
    var searchLoop: Double
    var handoffLoop: Double
    var chrome: PlaceTheme
    var session: PlaceSession
    var reduceMotion: Bool
    var haptics: HapticScheduler

    @ScaledMetric(relativeTo: .largeTitle) private var scaledHero: CGFloat = 80

    /// Driving `elapsed` as animatable data is what gives the whole reveal a
    /// single clock. `nil` means searching, which is not animated.
    var animatableData: Double {
        get { elapsed ?? 0 }
        set { elapsed = newValue }
    }

    private var postcode: UKPostcode { session.fix.postcode }
    private var heroText: String { postcode.formatted }

    private var sample: RevealSample {
        RevealTimeline.sample(
            elapsed: elapsed,
            searchLoop: searchLoop,
            handoffLoop: handoffLoop,
            outcodeCount: postcode.outcode.count,
            incodeCount: postcode.incode.count,
            reduceMotion: reduceMotion
        )
    }

    /// Drives the haptic scheduler against the clock. Skipped while searching
    /// (`elapsed == nil`, Act 1) and while Reduce Motion is on: Reduce Motion
    /// jumps `elapsed` straight to its final value with no intermediate
    /// frames (`RootView.beginReveal` assigns it outside `withAnimation`), so
    /// `advance` would see every cue at once and fire the whole schedule in a
    /// single burst. `RootView.beginReveal` fires one confirmation impact
    /// instead (`HapticScheduler.confirmSettled`).
    private func fireHaptics(elapsed: Double?) {
        guard let elapsed, !reduceMotion else { return }
        haptics.advance(
            to: elapsed,
            cues: RevealTimeline.hapticCues(
                outcodeCount: postcode.outcode.count,
                incodeCount: postcode.incode.count
            )
        )
    }

    var body: some View {
        let frame = sample
        // A bare `if` statement here would be parsed by the implicit
        // `@ViewBuilder` on `body` and fail to type-check, since its branch
        // has no View-producing expression (`haptics.advance` returns
        // `Void`). Routing it through a `let _ =` assignment keeps it a
        // plain statement the builder passes through untouched.
        let _ = fireHaptics(elapsed: elapsed)
        let theme = ThemeInterpolation.frame(
            from: chrome,
            to: session.fix.theme,
            t: frame.washProgress
        )

        GeometryReader { proxy in
            ZStack {
                wash(frame: frame, theme: theme, size: proxy.size)
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    stage(frame: frame, theme: theme, width: proxy.size.width)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea()
    }

    /// The colour the postcode emits. It grows from the hero's baseline
    /// outward, so it reads as coming from the code rather than from the
    /// window.
    ///
    /// Drawn as a hard-edged radial gradient on a screen-sized layer, not as
    /// a scaled `Circle`. A circle large enough to cover the screen needs a
    /// frame of at least the screen's diagonal, and SwiftUI rasterises that
    /// frame: at `diagonal * 2` that is tens of millions of pixels every
    /// frame, which stalled the reveal to roughly one frame per second the
    /// instant the wash began.
    ///
    /// The corners are the last thing covered, so full coverage needs a
    /// radius of half the diagonal — `diagonal * 2` as a diameter was four
    /// times the area it needed, and it also meant the screen was fully
    /// washed at `washProgress` 0.5 rather than 1.
    private func wash(frame: RevealSample, theme: PlaceTheme, size: CGSize) -> some View {
        let corner = sqrt(size.width * size.width + size.height * size.height) / 2
        let edge = max(0.001, corner * 1.01 * frame.washProgress)
        let colour = session.fix.theme.primary.color
        return ZStack {
            chrome.primary.color
            Rectangle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: colour, location: 0),
                            .init(color: colour, location: 0.995),
                            .init(color: .clear, location: 1)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: edge
                    )
                )
                .opacity(frame.washProgress > 0 ? 1 : 0)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func stage(frame: RevealSample, theme: PlaceTheme, width: CGFloat) -> some View {
        VStack(spacing: 8) {
            Text(ProductCopy.nearest)
                .font(.system(.footnote, design: .rounded).weight(.medium))
                .foregroundStyle(theme.onPrimary.color.opacity(HeroType.mutedOpacity))
                .opacity(frame.sectionOpacity)
                // `heroLabel` on the characters already says "nearest
                // postcode"; leaving this visible to VoiceOver would make the
                // hero three stops instead of one and say it twice.
                .accessibilityHidden(true)

            ZStack {
                rings(frame: frame, color: chrome.onPrimary.color)
                line(frame: frame, color: theme.onPrimary.color, width: width)
                characters(frame: frame, color: theme.onPrimary.color, width: width)
            }
            .frame(height: 180)

            if let district = session.fix.district {
                Text(district)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .foregroundStyle(theme.accent.color)
                    .opacity(frame.districtOpacity)
                    .offset(y: CGFloat(frame.districtOffset))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                    // Also carried by `heroLabel`, for the same reason.
                    .accessibilityHidden(true)
            }

            // Always in the tree, governed by opacity alone. It used to be
            // gated on `elapsed == nil`, but `animatableData` can only write
            // a concrete Double, so the optional is already non-nil on the
            // reveal's first interpolated frame: the caption was cut in one
            // frame instead of fading over `captionOut`. Keeping it present
            // also keeps the stage's height constant, so nothing shifts when
            // it goes.
            VStack(spacing: 6) {
                Text(ProductCopy.findingTitle)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .foregroundStyle(chrome.onPrimary.color)
                Text(ProductCopy.findingCaption)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(chrome.onPrimary.color.opacity(0.62))
            }
            .multilineTextAlignment(.center)
            .opacity(frame.captionOpacity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(ProductCopy.findingTitle). \(ProductCopy.findingCaption)")
            .accessibilityHidden(frame.captionOpacity <= 0)
        }
        .padding(.horizontal, 24)
        .accessibilityElement(children: .contain)
    }

    private func rings(frame: RevealSample, color: Color) -> some View {
        ZStack {
            ForEach(Array(frame.rings.enumerated()), id: \.offset) { _, ring in
                Circle()
                    .stroke(color.opacity(ring.opacity), lineWidth: CGFloat(ring.lineWidth))
                    .frame(width: CGFloat(ring.radius * 2), height: CGFloat(ring.radius * 2))
            }
            Circle()
                .stroke(color.opacity(frame.lockOpacity * 0.9), lineWidth: 2)
                .frame(
                    width: CGFloat(frame.lockRadius * 2),
                    height: CGFloat(frame.lockRadius * 2)
                )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The lock stretched flat. It becomes the baseline the characters rise
    /// out of, then dissolves once they have arrived.
    private func line(frame: RevealSample, color: Color, width: CGFloat) -> some View {
        let available = max(1, width - 48)
        return Capsule()
            .fill(color.opacity(frame.lineOpacity))
            .frame(
                width: available * CGFloat(frame.lineLength),
                height: max(0.5, CGFloat(frame.lineThickness))
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func characters(frame: RevealSample, color: Color, width: CGFloat) -> some View {
        let available = max(1, width - 48)
        let size = HeroFitting.pointSize(
            text: heroText,
            availableWidth: available,
            scaledPreference: scaledHero
        )
        let advances = HeroFitting.characterAdvances(text: heroText, size: size)
        let total = HeroMetrics.totalWidth(
            advances: advances.map(Double.init),
            tracking: HeroType.tracking
        )
        let offsets = HeroMetrics.offsets(
            advances: advances.map(Double.init),
            tracking: HeroType.tracking
        )
        let glyphs = Array(heroText)

        return ZStack(alignment: .leading) {
            ForEach(glyphs.indices, id: \.self) { index in
                glyph(
                    glyphs[index],
                    state: state(frame: frame, glyphIndex: index),
                    size: size,
                    color: color
                )
                .frame(width: advances[index])
                .offset(x: CGFloat(offsets[index]))
            }
        }
        .frame(width: CGFloat(total), alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            ProductCopy.heroLabel(
                postcode: heroText,
                district: session.fix.district
            )
        )
    }

    /// The hero string carries a space between outcode and incode that the
    /// timeline does not animate, so glyph indices and character states are
    /// not the same sequence.
    private func state(frame: RevealSample, glyphIndex: Int) -> CharacterState {
        let glyphs = Array(heroText)
        let spaceIndex = postcode.outcode.count
        if glyphIndex == spaceIndex {
            return CharacterState(opacity: 0, offsetY: 0, scale: 1, weightBlend: 0)
        }
        let animated = glyphIndex < spaceIndex ? glyphIndex : glyphIndex - 1
        guard animated >= 0, animated < frame.characters.count, glyphIndex < glyphs.count else {
            return CharacterState(opacity: 1, offsetY: 0, scale: 1, weightBlend: 1)
        }
        return frame.characters[animated]
    }

    private func glyph(
        _ character: Character,
        state: CharacterState,
        size: CGFloat,
        color: Color
    ) -> some View {
        ZStack {
            Text(String(character))
                .font(.system(size: size, weight: .medium, design: .rounded))
                .opacity(1 - state.weightBlend)
            Text(String(character))
                .font(.system(size: size, weight: .bold, design: .rounded))
                .opacity(state.weightBlend)
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .fixedSize()
        .scaleEffect(CGFloat(max(0.01, state.scale)))
        .offset(y: CGFloat(state.offsetY))
        .opacity(state.opacity)
    }
}
