import PlacodeCore
import SwiftUI

struct LocateChrome: View {
    var onPrimary: Color
    var showsBackground: Bool = true
    var background: Color = .black
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack {
            if showsBackground {
                background.ignoresSafeArea()
            }
            VStack(spacing: 0) {
                HStack {
                    Text(ProductCopy.wordmark)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(onPrimary.opacity(0.55))
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .accessibilityHidden(true)
                Spacer()
            }
            VStack(spacing: 28) {
                pulseRing
                VStack(spacing: 6) {
                    Text(ProductCopy.findingTitle)
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .foregroundStyle(onPrimary)
                    Text(ProductCopy.findingCaption)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(onPrimary.opacity(0.62))
                }
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(ProductCopy.findingTitle). \(ProductCopy.findingCaption)")
        }
    }

    private var pulseRing: some View {
        ZStack {
            if reduceMotion {
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(onPrimary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(-90))
            } else {
                ring(diameter: 148, base: 0.08)
                ring(diameter: 108, base: 0.14)
                Circle()
                    .stroke(onPrimary.opacity(0.28), lineWidth: 1.5)
                    .frame(width: 72, height: 72)
                ProgressView()
                    .controlSize(.large)
                    .tint(onPrimary)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 160, height: 160)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: MotionTiming.pulseLoop).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private func ring(diameter: CGFloat, base: Double) -> some View {
        Circle()
            .stroke(onPrimary.opacity(pulse ? base + MotionTiming.pulseAmplitude : base), lineWidth: 1)
            .frame(width: diameter, height: diameter)
    }
}
