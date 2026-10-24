import PostcodeNowCore
import SwiftUI
import UIKit

@MainActor
struct RootView: View {
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = AppModel(location: LocationService(), client: .live())

    /// nil while searching; seconds since the fix landed once it has. This is
    /// the reveal's single clock, driven by `withAnimation` and interpolated
    /// by the `Animatable` views that read it.
    @State private var revealElapsed: Double?

    /// Wall clock for Act 1. The loop phase is derived from this per frame
    /// instead of being held in state, because a `@State` mutated inside
    /// `withAnimation` is already at its target the moment anyone reads it —
    /// it could never tell `beginReveal` where the rings actually are.
    @State private var searchStart = Date()

    /// The search loop's phase frozen at the instant the fix landed, so Act 2
    /// collapses the rings from where they were rather than from a canonical
    /// position.
    @State private var handoffLoop: Double = 0

    /// Wall clock for the reveal, kept only to answer "is it still running?".
    /// `revealElapsed` cannot answer that: it holds the animation's target,
    /// not the frame being shown.
    @State private var revealStart: Date?

    /// Bumped whenever the reveal is started, skipped or settled early, which
    /// invalidates any VoiceOver announcement still waiting to fire.
    @State private var revealToken = 0

    var body: some View {
        @Bindable var model = model
        let chrome = systemScheme == .dark ? PlaceTheme.locateDark : PlaceTheme.locateLight

        ZStack {
            reveal(chrome: chrome)
                .allowsHitTesting(!showsEdgeScreen)
                .accessibilityHidden(showsEdgeScreen)
            // The crossfade is scoped to the edge screens on purpose: over
            // the whole stack it would also animate the canvas's values on
            // every edge transition, and it puts an `.animation(_:value:)`
            // in the path of the reveal's own `withAnimation` for no reason.
            // (Measured: an enclosing `.animation(_:value:)` whose value does
            // not change does not in fact swallow the reveal's clock — the
            // scrim's one in `PlaceExperience` sits above the canvas today
            // and the reveal interpolates correctly through it.)
            edgeScreen
                .animation(.easeInOut(duration: MotionTiming.edgeCrossfade), value: edgeKey)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(forcedScheme)
        .background {
            SharePresenter(
                isPresented: $model.isSharing,
                text: model.shareText ?? "",
                interfaceStyle: model.systemScheme == .dark ? .dark : .light
            )
        }
        .onAppear {
            model.systemScheme = systemScheme
            model.start()
            startSearchLoop()
        }
        .onChange(of: systemScheme) { _, newValue in
            model.systemScheme = newValue
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.resumeIfNeeded()
                settleIfInterrupted()
            }
        }
        // Reduce Motion can be turned on mid-reveal, without the app ever
        // leaving the foreground, by the Accessibility Shortcut. The canvas
        // handles that on its own — `RevealTimeline.sample` resolves to the
        // settled frame before it reads the clock at all — but the clock
        // itself would stay mid-flight: a pending announcement would still be
        // waiting out the rest of a reveal that is already over, and `skip`
        // would still believe one was running. Settling it keeps the state
        // honest about what is on screen.
        .onChange(of: reduceMotion) { _, isOn in
            if isOn { settleIfInterrupted() }
        }
        .onChange(of: model.phase) { _, newPhase in
            handlePhaseChange(newPhase)
        }
    }

    /// One canvas, alive from launch to settle. Searching and revealing are
    /// the same view with a different clock: if SwiftUI were allowed to remove
    /// one and insert the other — which is what a `switch` over the phase does,
    /// since each branch is its own identity — the user would see a cut no
    /// matter how well the timings lined up. The edge screens are the only
    /// thing that swaps, and they cover the canvas rather than replacing it.
    @ViewBuilder
    private func reveal(chrome: PlaceTheme) -> some View {
        if reduceMotion {
            settled(chrome: chrome)
        } else {
            TimelineView(.animation(paused: !isScanning)) { context in
                canvas(
                    chrome: chrome,
                    searchLoop: Self.loopPhase(from: searchStart, to: context.date)
                )
            }
            .contentShape(Rectangle())
            .onTapGesture { skip() }
        }
    }

    /// Reduce Motion gets no canvas while searching: the canvas resolves to
    /// the fully settled state, which for a placeholder session would mean
    /// showing a postcode that is not the user's.
    @ViewBuilder
    private func settled(chrome: PlaceTheme) -> some View {
        if case .place = model.phase {
            canvas(chrome: chrome, searchLoop: 0)
        } else {
            LocateChrome(onPrimary: chrome.onPrimary.color, background: chrome.primary.color)
        }
    }

    private func canvas(chrome: PlaceTheme, searchLoop: Double) -> some View {
        PlaceExperience(
            session: displaySession,
            chrome: chrome,
            reduceMotion: reduceMotion,
            isSharing: model.isSharing,
            toastToken: model.toastToken,
            elapsed: revealElapsed,
            searchLoop: searchLoop,
            handoffLoop: handoffLoop,
            onShare: { model.sharePostcode() },
            onCopy: { model.copyPostcode() },
            onRetry: { model.start() }
        )
    }

    @ViewBuilder
    private var edgeScreen: some View {
        switch model.phase {
        case .permissionDenied:
            PermissionScreen(onOpenSettings: { model.openSettings() })
                .transition(.opacity)
        case .failed(let failure):
            FailureScreen(failure: failure, onRetry: { model.start() })
                .transition(.opacity)
        case .unsupported:
            UnsupportedScreen(onRetry: { model.start() })
                .transition(.opacity)
        case .locating, .place:
            EmptyView()
        }
    }

    /// The real session once there is one, and a stand-in before that so the
    /// canvas can exist before a postcode does. The stand-in's characters are
    /// never visible, because `elapsed` is nil until the real one arrives.
    private var displaySession: PlaceSession {
        if case .place(let session) = model.phase {
            return session
        }
        return Self.placeholderSession
    }

    private static let placeholderSession = PlaceSession(
        fix: PostcodeFix(
            postcode: UKPostcode(outcode: "M1", incode: "1AE")!,
            district: nil,
            theme: .neutral
        ),
        quality: .precise,
        isOutdated: false,
        token: 0
    )

    /// Changes only when we move between edge destinations, so the crossfade
    /// never fires for the locating-to-place handoff, which must be seamless.
    private var edgeKey: Int {
        switch model.phase {
        case .locating, .place: return 0
        case .permissionDenied: return 1
        case .failed: return 2
        case .unsupported: return 3
        }
    }

    private var showsEdgeScreen: Bool { edgeKey != 0 }

    /// True only while Act 1 is on screen. Everything else pauses the
    /// timeline, so the display link is not driving frames behind an edge
    /// screen or after the code has settled.
    private var isScanning: Bool {
        guard revealElapsed == nil else { return false }
        if case .locating = model.phase { return true }
        return false
    }

    /// Act 1's phase in 0..<1 at a given instant.
    private static func loopPhase(from start: Date, to now: Date) -> Double {
        let phase = (now.timeIntervalSince(start) / RevealTiming.scanLoop)
            .truncatingRemainder(dividingBy: 1)
        return phase < 0 ? phase + 1 : phase
    }

    private func startSearchLoop() {
        searchStart = Date()
    }

    private func handlePhaseChange(_ phase: Phase) {
        switch phase {
        case .place(let session):
            beginReveal(session: session)
        case .locating:
            revealElapsed = nil
            revealStart = nil
            revealToken += 1
            startSearchLoop()
        default:
            revealElapsed = nil
            revealStart = nil
            revealToken += 1
        }
    }

    private func beginReveal(session: PlaceSession) {
        let total = Self.duration(of: session)
        revealToken += 1
        guard !reduceMotion else {
            revealStart = nil
            revealElapsed = total
            announceSettled(session: session, after: 0)
            return
        }
        // Freeze where the rings actually are, so Act 2 starts from there.
        handoffLoop = Self.loopPhase(from: searchStart, to: Date())
        revealStart = Date()
        revealElapsed = 0
        withAnimation(.linear(duration: total)) {
            revealElapsed = total
        }
        announceSettled(session: session, after: total)
    }

    /// A tap ends the reveal early. The target has to be a value the state
    /// does not already hold: `withAnimation` set `revealElapsed` to `total`
    /// the instant the reveal began, so assigning `total` again would not be
    /// a change and would leave the in-flight animation running. Landing a
    /// hair past the end is a real change, and the timeline treats anything
    /// at or beyond `total` as settled.
    private func skip() {
        guard case .place(let session) = model.phase, isRevealInFlight else { return }
        revealToken += 1
        withAnimation(.easeOut(duration: MotionTiming.skipCrossfade)) {
            revealElapsed = Self.duration(of: session) + Self.settleNudge
        }
        announceSettled(session: session, after: MotionTiming.skipCrossfade)
    }

    /// Review Focus 5: SwiftUI does not advance animations in the background,
    /// so a reveal interrupted by a backgrounding would otherwise resume from
    /// a stale value or sit frozen mid-bloom. Landing it settled is the only
    /// honest option — the moment has passed.
    private func settleIfInterrupted() {
        guard case .place(let session) = model.phase, isRevealInFlight else { return }
        revealToken += 1
        withAnimation(.easeOut(duration: MotionTiming.reduceMotionCrossfade)) {
            revealElapsed = Self.duration(of: session) + Self.settleNudge
        }
        announceSettled(session: session, after: MotionTiming.reduceMotionCrossfade)
    }

    /// Asked of the wall clock, not of `revealElapsed`, for the reason given
    /// on `revealStart`.
    private var isRevealInFlight: Bool {
        guard case .place(let session) = model.phase, let revealStart else { return false }
        return Date().timeIntervalSince(revealStart) < Self.duration(of: session)
    }

    /// Spoken once the code has landed. Announcing mid-reveal would interrupt
    /// whatever VoiceOver is already reading and move focus off the user's
    /// place, so it waits for the end.
    private func announceSettled(session: PlaceSession, after delay: Double) {
        let label = ProductCopy.heroLabel(
            postcode: session.fix.postcode.formatted,
            district: session.fix.district
        )
        let token = revealToken
        Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard token == revealToken else { return }
            UIAccessibility.post(notification: .announcement, argument: label)
        }
    }

    private static func duration(of session: PlaceSession) -> Double {
        RevealTimeline.duration(
            outcodeCount: session.fix.postcode.outcode.count,
            incodeCount: session.fix.postcode.incode.count
        )
    }

    /// Small enough to be invisible, large enough to be a distinct `Double`.
    private static let settleNudge: Double = 0.001

    private var forcedScheme: ColorScheme? {
        guard case .place(let session) = model.phase else { return nil }
        return session.fix.theme.primary.isLight ? .light : .dark
    }
}
