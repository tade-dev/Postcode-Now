import PostcodeNowCore
import SwiftUI

/// The static locate screen. Animated scanning now lives in RevealCanvas;
/// this is what Reduce Motion and the pre-session moment show instead.
struct LocateChrome: View {
    var onPrimary: Color
    var showsBackground: Bool = true
    var background: Color = .black

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
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(onPrimary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(-90))
                    .frame(width: 160, height: 160)
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
}
