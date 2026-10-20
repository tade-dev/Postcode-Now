import PostcodeNowCore
import SwiftUI

/// Re-renders its content against the reveal's interpolated clock.
///
/// A plain read of `elapsed` is the animation's *target*, not the frame being
/// shown: `withAnimation` sets state immediately and only `Animatable` views
/// see the values in between. Sampling the timeline from that target ramped
/// the CTA in linearly across the whole reveal instead of springing it in at
/// the end, and left the buttons hit-testable from its first frame.
/// `RevealCanvas` solves this for the canvas; this does it for the chrome
/// that sits outside the canvas.
private struct RevealClock<Content: View>: View, Animatable {
    var elapsed: Double?
    @ViewBuilder var content: (Double?) -> Content

    var animatableData: Double {
        get { elapsed ?? 0 }
        set { elapsed = newValue }
    }

    var body: some View {
        content(elapsed)
    }
}

/// Hosts the canvas and everything the timeline does not drive: the buttons,
/// the notice banner, the share scrim, the copied toast.
struct PlaceExperience: View {
    var session: PlaceSession
    var chrome: PlaceTheme
    var reduceMotion: Bool
    var isSharing: Bool
    var toastToken: Int
    var elapsed: Double?
    var searchLoop: Double
    var handoffLoop: Double
    var onShare: () -> Void
    var onCopy: () -> Void
    var onRetry: () -> Void

    private func sample(at elapsed: Double?) -> RevealSample {
        RevealTimeline.sample(
            elapsed: elapsed,
            searchLoop: searchLoop,
            handoffLoop: handoffLoop,
            outcodeCount: session.fix.postcode.outcode.count,
            incodeCount: session.fix.postcode.incode.count,
            reduceMotion: reduceMotion
        )
    }

    private func theme(_ frame: RevealSample) -> PlaceTheme {
        ThemeInterpolation.frame(from: chrome, to: session.fix.theme, t: frame.washProgress)
    }

    var body: some View {
        ZStack {
            RevealCanvas(
                elapsed: elapsed,
                searchLoop: searchLoop,
                handoffLoop: handoffLoop,
                chrome: chrome,
                session: session,
                reduceMotion: reduceMotion
            )
            RevealClock(elapsed: elapsed) { now in
                let frame = sample(at: now)
                VStack(spacing: 0) {
                    header(frame: frame, theme: theme(frame))
                    Spacer(minLength: 0)
                }
            }
            Color.black
                .opacity(isSharing ? 0.4 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(isSharing)
                .accessibilityHidden(true)
                .animation(
                    .easeOut(duration: isSharing ? MotionTiming.scrimIn : MotionTiming.scrimOut),
                    value: isSharing
                )
            VStack {
                CopiedToast(token: toastToken)
                    .padding(.top, 8)
                Spacer()
            }
        }
        .scaleEffect(isSharing ? 0.98 : 1)
        .animation(
            .easeOut(duration: isSharing ? MotionTiming.scrimIn : MotionTiming.scrimOut),
            value: isSharing
        )
        .safeAreaInset(edge: .bottom, spacing: 16) {
            RevealClock(elapsed: elapsed) { now in
                let frame = sample(at: now)
                controls(frame: frame, theme: theme(frame))
            }
        }
    }

    @ViewBuilder
    private func header(frame: RevealSample, theme: PlaceTheme) -> some View {
        if session.isOutdated || session.quality == .approximate {
            banner(theme: theme)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .opacity(frame.bannerOpacity)
                .accessibilitySortPriority(2)
        } else {
            HStack {
                Text(ProductCopy.wordmark)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(theme.onPrimary.color.opacity(HeroType.mutedOpacity))
                    .opacity(frame.wordmarkOpacity)
                    .accessibilityHidden(true)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
        }
    }

    private func controls(frame: RevealSample, theme: PlaceTheme) -> some View {
        VStack(spacing: 8) {
            if session.isOutdated || session.quality == .approximate {
                PrimaryButton(
                    title: session.isOutdated ? ProductCopy.retry : ProductCopy.tryAgain,
                    fill: theme.accent.color,
                    label: theme.onAccent.color,
                    action: onRetry
                )
                SecondaryFillButton(
                    title: ProductCopy.shareAnyway,
                    foreground: theme.onPrimary.color,
                    action: onShare
                )
            } else {
                PrimaryButton(
                    title: ProductCopy.share,
                    fill: theme.accent.color,
                    label: theme.onAccent.color,
                    action: onShare
                )
                SecondaryTextButton(
                    title: ProductCopy.copy,
                    color: theme.onPrimary.color,
                    action: onCopy
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .opacity(frame.ctaOpacity)
        .offset(y: CGFloat(frame.ctaOffset))
        .allowsHitTesting(frame.ctaOpacity > 0.9)
        .accessibilitySortPriority(1)
    }

    @ViewBuilder
    private func banner(theme: PlaceTheme) -> some View {
        if session.isOutdated {
            NoticeBanner(
                title: ProductCopy.outdatedTitle,
                message: ProductCopy.outdatedBody,
                symbol: "info.circle.fill",
                foreground: theme.onPrimary.color,
                background: bannerFill(theme),
                edge: theme.onPrimary.color.opacity(0.7)
            )
        } else if session.quality == .approximate {
            NoticeBanner(
                title: ProductCopy.weakTitle,
                message: ProductCopy.weakBody,
                symbol: "exclamationmark.circle.fill",
                foreground: theme.onPrimary.color,
                background: bannerFill(theme),
                edge: Color(hex: 0xFF9F0A)
            )
        }
    }

    private func bannerFill(_ theme: PlaceTheme) -> Color {
        theme.primary.isLight ? Color.white.opacity(0.62) : Color.black.opacity(0.28)
    }
}

#Preview("M1 ready") {
    PlaceExperience(
        session: previewSession(outcode: "M1", incode: "1AE", district: "Manchester"),
        chrome: .locateDark,
        reduceMotion: true,
        isSharing: false,
        toastToken: 0,
        elapsed: RevealTimeline.duration(outcodeCount: 2, incodeCount: 3),
        searchLoop: 0,
        handoffLoop: 0,
        onShare: {},
        onCopy: {},
        onRetry: {}
    )
}

#Preview("EX1 ready") {
    PlaceExperience(
        session: previewSession(outcode: "EX1", incode: "1AA", district: "East Devon"),
        chrome: .locateLight,
        reduceMotion: true,
        isSharing: false,
        toastToken: 0,
        elapsed: RevealTimeline.duration(outcodeCount: 2, incodeCount: 3),
        searchLoop: 0,
        handoffLoop: 0,
        onShare: {},
        onCopy: {},
        onRetry: {}
    )
    .preferredColorScheme(.light)
}

#Preview("Weak GPS") {
    PlaceExperience(
        session: previewSession(
            outcode: "M1",
            incode: "1AE",
            district: "Manchester",
            quality: .approximate
        ),
        chrome: .locateDark,
        reduceMotion: true,
        isSharing: false,
        toastToken: 0,
        elapsed: RevealTimeline.duration(outcodeCount: 2, incodeCount: 3),
        searchLoop: 0,
        handoffLoop: 0,
        onShare: {},
        onCopy: {},
        onRetry: {}
    )
}

#Preview("Searching") {
    PlaceExperience(
        session: previewSession(outcode: "M1", incode: "1AE", district: "Manchester"),
        chrome: .locateDark,
        reduceMotion: false,
        isSharing: false,
        toastToken: 0,
        elapsed: nil,
        searchLoop: 0.4,
        handoffLoop: 0,
        onShare: {},
        onCopy: {},
        onRetry: {}
    )
}

#Preview("SW1A widest") {
    PlaceExperience(
        session: previewSession(outcode: "SW1A", incode: "1AA", district: "Westminster"),
        chrome: .locateDark,
        reduceMotion: true,
        isSharing: false,
        toastToken: 0,
        elapsed: RevealTimeline.duration(outcodeCount: 4, incodeCount: 3),
        searchLoop: 0,
        handoffLoop: 0,
        onShare: {},
        onCopy: {},
        onRetry: {}
    )
    .environment(\.dynamicTypeSize, .accessibility5)
}

private func previewSession(
    outcode: String,
    incode: String,
    district: String?,
    quality: LocationQuality = .precise,
    outdated: Bool = false
) -> PlaceSession {
    let postcode = UKPostcode(outcode: outcode, incode: incode)!
    let fix = PostcodeFix(
        postcode: postcode,
        district: district,
        theme: PlacePalette.resolve(outcode: outcode, district: district)
    )
    return PlaceSession(fix: fix, quality: quality, isOutdated: outdated, token: 1)
}
