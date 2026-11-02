
import SwiftUI
import UIKit

struct HomeView: View {
    let tagline: String
    let onDiscover: () -> Void
    let onModules: () -> Void

    @State private var selectedCategory = "All"
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let categories = [
        "All", "Movies", "Series", "Anime", "Manga"
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 27) {
                header
                    .entrance(appeared, delay: 0.02)

                introduction
                    .entrance(appeared, delay: 0.08)

                heroCard
                    .entrance(appeared, delay: 0.14)

                categorySection
                    .entrance(appeared, delay: 0.20)

                mediaSection
                    .entrance(appeared, delay: 0.26)

                moduleCard
                    .entrance(appeared, delay: 0.32)
            }
            .padding(.horizontal, 21)
            .padding(.top, 16)
            .padding(.bottom, 30)
        }
        .background(Color(uiColor: .systemBackground))
        .onAppear {
            withAnimation(
                reduceMotion
                ? .easeInOut(duration: 0.2)
                : .spring(response: 0.72, dampingFraction: 0.88)
            ) {
                appeared = true
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(
                    LinearGradient(
                        colors: [KinetiqPalette.cyan, KinetiqPalette.violet],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .shadow(
                    color: KinetiqPalette.blue.opacity(0.25),
                    radius: 12,
                    x: 0,
                    y: 5
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("KINETIQ")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .tracking(2.2)

                Text("YOUR MEDIA UNIVERSE")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onDiscover) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .background(
                        Color(uiColor: .secondarySystemGroupedBackground),
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search and discover")
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("ONE HOME. EVERY STORY.")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(2.4)
                .foregroundStyle(KinetiqPalette.accent)

            Text("Your world of media.")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .tracking(-1.25)
                .fixedSize(horizontal: false, vertical: true)

            Text(
                tagline.isEmpty
                ? "Movies, series, anime and manga -- all moving together."
                : tagline
            )
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    private var heroCard: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.08, green: 0.20, blue: 0.38),
                            Color(red: 0.13, green: 0.34, blue: 0.57),
                            Color(red: 0.34, green: 0.22, blue: 0.58)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            GeometryReader { proxy in
                ZStack {
                    Circle()
                        .fill(KinetiqPalette.cyan.opacity(0.22))
                        .frame(width: 210, height: 210)
                        .offset(x: proxy.size.width * 0.43, y: -58)

                    Circle()
                        .stroke(.white.opacity(0.13), lineWidth: 1)
                        .frame(width: 235, height: 235)
                        .offset(x: proxy.size.width * 0.38, y: -48)

                    Circle()
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                        .frame(width: 285, height: 285)
                        .offset(x: proxy.size.width * 0.38, y: -48)

                    Image(systemName: "play.rectangle.on.rectangle.fill")
                        .font(.system(size: 76, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.18))
                        .rotationEffect(.degrees(-13))
                        .offset(x: proxy.size.width * 0.30, y: -8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(KinetiqPalette.cyan)
                        .frame(width: 6, height: 6)

                    Text("THE KINETIQ EXPERIENCE")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1.8)
                        .foregroundStyle(.white.opacity(0.82))
                }

                Text("Every kind of story.\nOne place to find it.")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .tracking(-0.8)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text("A universe built around what you love.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))

                Button(action: onDiscover) {
                    HStack(spacing: 9) {
                        Text("Explore Kinetiq")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(red: 0.10, green: 0.20, blue: 0.34))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .padding(21)
        }
        .frame(height: 258)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
        .shadow(
            color: KinetiqPalette.blue.opacity(0.20),
            radius: 22,
            x: 0,
            y: 12
        )
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionHeading(
                "Explore your way",
                detail: "THE WHOLE UNIVERSE"
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { category in
                        Button {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                selectedCategory = category
                            }
                            onDiscover()
                        } label: {
                            Text(category)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(
                                    selectedCategory == category
                                    ? .white
                                    : Color.primary.opacity(0.78)
                                )
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    selectedCategory == category
                                    ? KinetiqPalette.accent
                                    : Color(uiColor: .secondarySystemGroupedBackground),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionHeading(
                "A universe of possibilities",
                detail: "MADE FOR EVERY MOOD"
            )

            HStack(spacing: 11) {
                MediaTypeCard(
                    title: "Movies",
                    subtitle: "Big-screen stories",
                    symbol: "film",
                    colors: [KinetiqPalette.blue, KinetiqPalette.violet]
                )

                MediaTypeCard(
                    title: "Series",
                    subtitle: "One more episode",
                    symbol: "tv",
                    colors: [KinetiqPalette.cyan, KinetiqPalette.blue]
                )
            }

            HStack(spacing: 11) {
                MediaTypeCard(
                    title: "Anime",
                    subtitle: "Worlds beyond",
                    symbol: "sparkles",
                    colors: [KinetiqPalette.violet, KinetiqPalette.blue]
                )

                MediaTypeCard(
                    title: "Manga",
                    subtitle: "Stories in panels",
                    symbol: "book.closed",
                    colors: [KinetiqPalette.blue, KinetiqPalette.cyan]
                )
            }
        }
    }

    private var moduleCard: some View {
        Button(action: onModules) {
            HStack(spacing: 14) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(KinetiqPalette.accent)
                    .frame(width: 46, height: 46)
                    .background(
                        KinetiqPalette.accent.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Your sources. Your rules.")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("The modular engine is part of the journey.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(15)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private func sectionHeading(
        _ title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .tracking(-0.35)

            Spacer(minLength: 8)

            Text(detail)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct MediaTypeCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    let colors: [Color]

    @State private var pressed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: colors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .scaleEffect(pressed ? 0.975 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.62), value: pressed)
        .onLongPressGesture(
            minimumDuration: 0.01,
            pressing: { pressing in
                pressed = pressing
            },
            perform: {}
        )
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    func entrance(_ appeared: Bool, delay: Double) -> some View {
        self
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 13)
            .animation(
                .spring(response: 0.62, dampingFraction: 0.88)
                    .delay(delay),
                value: appeared
            )
    }
}