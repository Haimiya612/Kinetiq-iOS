import SwiftUI
import UIKit

struct HomeView: View {
    let tagline: String

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    brandHeader
                    introduction
                    heroCard
                    foundationSection
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 32)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [KinetiqPalette.cyan, KinetiqPalette.violet],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "waveform")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 43, height: 43)

            VStack(alignment: .leading, spacing: 1) {
                Text("KINETIQ")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .tracking(2.4)
                Text("PLAYER")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .tracking(2.8)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "sparkle")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(KinetiqPalette.accent)
                .padding(12)
                .background(.thinMaterial, in: Circle())
                .accessibilityHidden(true)
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("A NEW KIND OF MEDIA SPACE")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(2.3)
                .foregroundStyle(KinetiqPalette.accent)

            Text("Your media,\nin motion.")
                .font(.system(size: 43, weight: .bold, design: .rounded))
                .tracking(-1.7)
                .lineSpacing(-3)
                .fixedSize(horizontal: false, vertical: true)

            Text(tagline)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .accessibilityLabel("Kinetiq tagline: \(tagline)")
        }
        .padding(.top, 12)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("THE PLAYER", systemImage: "play.circle.fill")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.3)
                Spacer()
                Text("FOUNDATION")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.16), in: Capsule())
            }
            .foregroundStyle(.white.opacity(0.88))

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("A space for\nevery story.")
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .tracking(-0.8)
                        .foregroundStyle(.white)
                    Text("Your player experience starts here.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                }
                Spacer(minLength: 0)
                Image(systemName: "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(red: 0.16, green: 0.22, blue: 0.34))
                    .frame(width: 51, height: 51)
                    .background(.white, in: Circle())
                    .accessibilityHidden(true)
            }
        }
        .padding(21)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.12, green: 0.57, blue: 0.72),
                            Color(red: 0.24, green: 0.38, blue: 0.77),
                            Color(red: 0.43, green: 0.28, blue: 0.69)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(.white.opacity(0.08))
                        .frame(width: 190, height: 190)
                        .blur(radius: 1)
                        .offset(x: 58, y: -82)
                        .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
                }
        }
        .shadow(color: KinetiqPalette.blue.opacity(0.18), radius: 22, x: 0, y: 12)
    }

    private var foundationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Built around you")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Spacer()
                Text("THE KINETIQ IDEA")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                FeatureTile(
                    icon: "square.stack.3d.up.fill",
                    title: "Modular",
                    detail: "Your sources. Your rules."
                )
                FeatureTile(
                    icon: "slider.horizontal.3",
                    title: "Personal",
                    detail: "A space that feels yours."
                )
            }
        }
    }
}

private struct FeatureTile: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(KinetiqPalette.accent)
                .frame(width: 36, height: 36)
                .background(KinetiqPalette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))

            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
            Text(detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .padding(15)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
