import PlacodeCore
import SwiftUI

@MainActor
struct RootView: View {
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = AppModel(location: LocationService(), client: .live())

    var body: some View {
        @Bindable var model = model
        let chrome = systemScheme == .dark ? PlaceTheme.locateDark : PlaceTheme.locateLight
        ZStack {
            switch model.phase {
            case .locating:
                LocateChrome(onPrimary: chrome.onPrimary.color, background: chrome.primary.color)
            case .permissionDenied:
                PermissionScreen(onOpenSettings: { model.openSettings() })
            case .failed(let failure):
                FailureScreen(failure: failure, onRetry: { model.start() })
            case .unsupported:
                UnsupportedScreen(onRetry: { model.start() })
            case .place(let session):
                PlaceExperience(
                    session: session,
                    chrome: chrome,
                    reduceMotion: reduceMotion,
                    isSharing: model.isSharing,
                    toastToken: model.toastToken,
                    onShare: { model.sharePostcode() },
                    onCopy: { model.copyPostcode() },
                    onRetry: { model.start() }
                )
                .id(session.token)
            }
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
        }
        .onChange(of: systemScheme) { _, newValue in
            model.systemScheme = newValue
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.resumeIfNeeded()
            }
        }
    }

    private var forcedScheme: ColorScheme? {
        guard case .place(let session) = model.phase else { return nil }
        return session.fix.theme.primary.isLight ? .light : .dark
    }
}
