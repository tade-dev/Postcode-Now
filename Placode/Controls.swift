import PlacodeCore
import SwiftUI
import UIKit

extension RGB {
    var color: Color {
        Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}

extension Color {
    init(hex: UInt32) {
        self = RGB(hex: hex).color
    }
}

struct PressFeedbackStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct PrimaryButton: View {
    var title: String
    var fill: Color
    var label: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(label)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressFeedbackStyle())
    }
}

struct SecondaryFillButton: View {
    var title: String
    var foreground: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    foreground.opacity(0.18),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(PressFeedbackStyle())
    }
}

struct SecondaryTextButton: View {
    var title: String
    var color: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressFeedbackStyle())
    }
}

struct NeutralChromeButton: View {
    var title: String
    var action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        PrimaryButton(
            title: title,
            fill: colorScheme == .dark ? Color(hex: 0x0A84FF) : Color(hex: 0x007AFF),
            label: .white,
            action: action
        )
    }
}

struct NoticeBanner: View {
    var title: String
    var message: String
    var symbol: String
    var foreground: Color
    var background: Color
    var edge: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(edge)
                .accessibilityHidden(true)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                Text(message)
                    .font(.system(.subheadline, design: .rounded))
                    .opacity(0.85)
            }
            .foregroundStyle(foreground)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.leading, 14)
        .padding(.trailing, 14)
        .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(edge)
                .frame(width: 4)
                .padding(.vertical, 8)
                .padding(.leading, 5)
        }
        .accessibilityElement(children: .combine)
    }
}

struct CopiedToast: View {
    var token: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    @State private var offset: CGFloat = 0
    @State private var dismiss: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(hex: 0x30D158))
                .accessibilityHidden(true)
            Text(ProductCopy.copied)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(hex: 0x1C1C1E), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
        .opacity(visible ? 1 : 0)
        .offset(y: offset)
        .allowsHitTesting(false)
        .accessibilityHidden(!visible)
        .accessibilityLabel(ProductCopy.copied)
        .onChange(of: token) { _, newValue in
            guard newValue > 0 else { return }
            present()
        }
    }

    private func present() {
        dismiss?.cancel()
        UIAccessibility.post(notification: .announcement, argument: ProductCopy.copied)
        if reduceMotion {
            offset = 0
            visible = true
        } else {
            offset = -6
            visible = false
            withAnimation(.easeOut(duration: MotionTiming.toastIn)) {
                visible = true
                offset = 0
            }
        }
        dismiss = Task {
            let hold = MotionTiming.toastIn + MotionTiming.toastHold
            try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if reduceMotion {
                visible = false
            } else {
                withAnimation(.easeOut(duration: MotionTiming.toastOut)) {
                    visible = false
                }
            }
        }
    }
}

final class LockTick {
    private var fired = false

    func consider(elapsed: Double, enabled: Bool) {
        guard enabled, !fired, elapsed >= MotionTiming.incodeDelay else { return }
        fired = true
        DispatchQueue.main.async {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    }
}
