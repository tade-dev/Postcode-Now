import PlacodeCore
import SwiftUI

struct NeutralScreen<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color.black : Color(hex: 0xF2F2F7)).ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                content()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct PermissionScreen: View {
    var onOpenSettings: () -> Void

    var body: some View {
        NeutralScreen {
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 88, height: 88)
                    Image(systemName: "mappin")
                        .font(.system(size: 32, weight: .regular))
                        .foregroundStyle(Color.primary.opacity(0.9))
                }
                .accessibilityHidden(true)
                .padding(.bottom, 6)
                Text(ProductCopy.permissionTitle)
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .multilineTextAlignment(.center)
                Text(ProductCopy.locationUsage)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text(ProductCopy.permissionPath)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
        .safeAreaInset(edge: .bottom) {
            NeutralChromeButton(title: ProductCopy.openSettings, action: onOpenSettings)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)
        }
    }
}

struct FailureScreen: View {
    var failure: Failure
    var onRetry: () -> Void

    var body: some View {
        NeutralScreen {
            VStack(spacing: 12) {
                Text(title)
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .safeAreaInset(edge: .bottom) {
            NeutralChromeButton(title: ProductCopy.retry, action: onRetry)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)
        }
    }

    private var title: String {
        switch failure {
        case .offline: return ProductCopy.offlineTitle
        case .notFound: return ProductCopy.notFoundTitle
        case .location: return ProductCopy.locationFailTitle
        case .other: return ProductCopy.otherFailTitle
        }
    }

    private var message: String {
        switch failure {
        case .offline: return ProductCopy.offlineBody
        case .notFound: return ProductCopy.notFoundBody
        case .location: return ProductCopy.locationFailBody
        case .other: return ProductCopy.otherFailBody
        }
    }
}

struct UnsupportedScreen: View {
    var onRetry: () -> Void

    var body: some View {
        NeutralScreen {
            VStack(spacing: 12) {
                Text(ProductCopy.unsupportedTitle)
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .multilineTextAlignment(.center)
                Text(ProductCopy.unsupportedBody)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .safeAreaInset(edge: .bottom) {
            NeutralChromeButton(title: ProductCopy.retry, action: onRetry)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)
        }
    }
}
