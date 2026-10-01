import PlacodeCore
import SwiftUI

struct PlaceExperience: View {
    var session: PlaceSession
    var chrome: PlaceTheme
    var reduceMotion: Bool
    var isSharing: Bool
    var toastToken: Int
    var onShare: () -> Void
    var onCopy: () -> Void
    var onRetry: () -> Void

    @State private var elapsed: Double
    @State private var tick = LockTick()

    init(
        session: PlaceSession,
        chrome: PlaceTheme,
        reduceMotion: Bool,
        isSharing: Bool,
        toastToken: Int,
        onShare: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onRetry: @escaping () -> Void
    ) {
        self.session = session
        self.chrome = chrome
        self.reduceMotion = reduceMotion
        self.isSharing = isSharing
        self.toastToken = toastToken
        self.onShare = onShare
        self.onCopy = onCopy
        self.onRetry = onRetry
        _elapsed = State(initialValue: reduceMotion ? SettleTimeline.duration : 0)
    }

    var body: some View {
        ZStack {
            SettleCanvas(
                elapsed: elapsed,
                reduceMotion: reduceMotion,
                chrome: chrome,
                session: session,
                tick: tick,
                onShare: onShare,
                onCopy: onCopy,
                onRetry: onRetry
            )
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
        .onAppear(perform: play)
    }

    private func play() {
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: SettleTimeline.duration)) {
            elapsed = SettleTimeline.duration
        }
    }
}

private struct SettleCanvas: View, Animatable {
    var elapsed: Double
    var reduceMotion: Bool
    var chrome: PlaceTheme
    var session: PlaceSession
    var tick: LockTick
    @ScaledMetric(relativeTo: .largeTitle) private var scaledHero: CGFloat = 80
    var onShare: () -> Void
    var onCopy: () -> Void
    var onRetry: () -> Void

    var animatableData: Double {
        get { elapsed }
        set { elapsed = newValue }
    }

    var body: some View {
        let sample = SettleTimeline.sample(elapsed: elapsed, reduceMotion: reduceMotion)
        let theme = ThemeInterpolation.frame(from: chrome, to: session.fix.theme, t: sample.wash)
        let _ = tick.consider(elapsed: elapsed, enabled: !reduceMotion)
        ZStack {
            theme.primary.color.ignoresSafeArea()
            VStack(spacing: 0) {
                header(sample: sample, theme: theme)
                Spacer(minLength: 0)
                hero(sample: sample, theme: theme)
                    .accessibilitySortPriority(3)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if sample.locateOpacity > 0.02 {
                LocateChrome(onPrimary: chrome.onPrimary.color, showsBackground: false)
                    .opacity(sample.locateOpacity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 16) {
            controls(sample: sample, theme: theme)
        }
    }

    @ViewBuilder
    private func header(sample: SettleSample, theme: PlaceTheme) -> some View {
        if session.isOutdated || session.quality == .approximate {
            banner(sample: sample, theme: theme)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .opacity(sample.bannerOpacity)
                .accessibilitySortPriority(2)
        } else {
            HStack {
                Text(ProductCopy.wordmark)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(theme.onPrimary.color.opacity(HeroType.mutedOpacity))
                    .opacity(sample.wordmarkOpacity)
                    .accessibilityHidden(true)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
        }
    }

    private func controls(sample: SettleSample, theme: PlaceTheme) -> some View {
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
        .opacity(sample.ctaOpacity)
        .offset(y: CGFloat(sample.ctaOffset))
        .accessibilitySortPriority(1)
    }

    private func hero(sample: SettleSample, theme: PlaceTheme) -> some View {
        VStack(spacing: 8) {
            Text(ProductCopy.nearest)
                .font(.system(.footnote, design: .rounded).weight(.medium))
                .foregroundStyle(theme.onPrimary.color.opacity(HeroType.mutedOpacity))
                .opacity(sample.sectionOpacity)
            GeometryReader { proxy in
                let size = HeroFitting.pointSize(
                    text: session.fix.postcode.formatted,
                    availableWidth: proxy.size.width,
                    scaledPreference: scaledHero
                )
                postcode(size: size, sample: sample, color: theme.onPrimary.color)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .frame(height: 112)
            if let district = session.fix.district {
                Text(district)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .foregroundStyle(theme.accent.color)
                    .opacity(sample.placeOpacity)
                    .offset(y: CGFloat(sample.placeOffset))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            ProductCopy.heroLabel(
                postcode: session.fix.postcode.formatted,
                district: session.fix.district
            )
        )
    }

    private func postcode(size: CGFloat, sample: SettleSample, color: Color) -> some View {
        HStack(alignment: .center, spacing: 0) {
            Text(session.fix.postcode.outcode)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .tracking(CGFloat(HeroType.tracking))
                .scaleEffect(CGFloat(sample.outcodeScale))
                .offset(y: CGFloat(sample.outcodeOffset))
                .opacity(sample.outcodeOpacity)
            Text(" ")
                .font(.system(size: size, weight: .bold, design: .rounded))
            ZStack {
                Text(session.fix.postcode.incode)
                    .font(.system(size: size, weight: .medium, design: .rounded))
                    .tracking(CGFloat(HeroType.tracking))
                    .opacity(1 - sample.incodeWeight)
                Text(session.fix.postcode.incode)
                    .font(.system(size: size, weight: .bold, design: .rounded))
                    .tracking(CGFloat(HeroType.tracking))
                    .opacity(sample.incodeWeight)
            }
            .scaleEffect(CGFloat(max(sample.incodeScale, 0.01)))
            .opacity(sample.incodeOpacity)
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func banner(sample: SettleSample, theme: PlaceTheme) -> some View {
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
        onShare: {},
        onCopy: {},
        onRetry: {}
    )
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
