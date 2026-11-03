import SwiftUI
import UIKit

// MARK: - Home Media Mode

private enum HomeMediaMode: String, CaseIterable, Identifiable {
    case video = "Video"
    case manga = "Manga"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .video: "play.rectangle.fill"
        case .manga: "book.closed.fill"
        }
    }
}

// MARK: - Home View

struct HomeView: View {
    let tagline: String
    let continueWatching: [PlaybackHistoryEntry]

    let onDiscover: () -> Void
    let onModules: () -> Void
    let onContinueWatching: (PlaybackHistoryEntry) -> Void
    let onOpenLibrary: () -> Void

    @State private var selectedMode: HomeMediaMode = .video
    @State private var selectedSource = "Local Library"
    @State private var appeared = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 13) {
            sourcePicker
            mediaModeSwitcher

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 27) {
                    header

                    if selectedMode == .video {
                        videoContent
                    } else {
                        mangaPlaceholder
                    }
                }
                .padding(.horizontal, 21)
                .padding(.top, 12)
                .padding(.bottom, 30)
            }
        }
        .padding(.top, 10)
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

    // MARK: Source / Module Picker

    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("ACTIVE SOURCE")
                    .font(
                        .system(
                            size: 9,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .tracking(1.7)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("SOURCE")
                    .font(
                        .system(
                            size: 8,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .tracking(1.2)
                    .foregroundStyle(KinetiqPalette.accent)
            }

            Menu {
                Button {
                    selectedSource = "Local Library"
                } label: {
                    Label(
                        "Local Library",
                        systemImage: "iphone"
                    )
                }

                Divider()

                Button(action: onModules) {
                    Label(
                        "Manage Modules",
                        systemImage: "square.stack.3d.up.fill"
                    )
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "iphone")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(KinetiqPalette.accent)
                        .frame(width: 37, height: 37)
                        .background(
                            KinetiqPalette.accent.opacity(0.12),
                            in: RoundedRectangle(
                                cornerRadius: 12,
                                style: .continuous
                            )
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedSource)
                            .font(
                                .system(
                                    size: 14,
                                    weight: .bold,
                                    design: .rounded
                                )
                            )
                            .foregroundStyle(.primary)

                        Text("Personal media on this device")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(
                        cornerRadius: 17,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 17,
                        style: .continuous
                    )
                    .strokeBorder(
                        Color.primary.opacity(0.045),
                        lineWidth: 0.7
                    )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "Active source: \(selectedSource). Choose a source or manage modules."
            )
        }
        .padding(.horizontal, 21)
    }

    // MARK: Video / Manga Switcher

    private var mediaModeSwitcher: some View {
        HStack(spacing: 5) {
            ForEach(HomeMediaMode.allCases) { mode in
                Button {
                    withAnimation(
                        reduceMotion
                            ? .easeInOut(duration: 0.15)
                            : .spring(
                                response: 0.34,
                                dampingFraction: 0.78
                            )
                    ) {
                        selectedMode = mode
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: mode.symbol)
                            .font(.system(size: 13, weight: .semibold))

                        Text(mode.rawValue)
                            .font(
                                .system(
                                    size: 13,
                                    weight: .bold,
                                    design: .rounded
                                )
                            )
                    }
                    .foregroundStyle(
                        selectedMode == mode
                            ? .white
                            : Color.primary.opacity(0.72)
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        if selectedMode == mode {
                            RoundedRectangle(
                                cornerRadius: 13,
                                style: .continuous
                            )
                            .fill(KinetiqPalette.accent)
                        }
                    }
                    .contentShape(
                        RoundedRectangle(
                            cornerRadius: 13,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(
                    selectedMode == mode ? .isSelected : []
                )
            }
        }
        .padding(5)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(
                cornerRadius: 17,
                style: .continuous
            )
        )
        .padding(.horizontal, 21)
    }

    // MARK: Video Home

    private var videoContent: some View {
        VStack(alignment: .leading, spacing: 27) {
            introduction
                .entrance(appeared, delay: 0.04)

            heroCard
                .entrance(appeared, delay: 0.10)

            if !continueWatching.isEmpty {
                continueWatchingSection
                    .entrance(appeared, delay: 0.16)
            }

            librarySection
                .entrance(appeared, delay: 0.22)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image("KinetiqLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 50, height: 50)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 16,
                        style: .continuous
                    )
                )
                .shadow(
                    color: KinetiqPalette.blue.opacity(0.20),
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
            .accessibilityLabel("Search and discover")
        }
    }

    // MARK: Introduction

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
                    ? "Movies, series and anime -- all moving together."
                    : tagline
            )
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    // MARK: Hero Card

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
                    .foregroundStyle(
                        Color(red: 0.10, green: 0.20, blue: 0.34)
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(.white, in: Capsule())
                }
                .padding(.top, 2)
            }
            .padding(21)
        }
        .frame(height: 258)
        .clipShape(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
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

    // MARK: Continue Watching

    private var continueWatchingSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionHeading(
                "Continue watching",
                detail: "PICK UP WHERE YOU LEFT OFF"
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(continueWatching) { entry in
                        Button {
                            onContinueWatching(entry)
                        } label: {
                            continueWatchingCard(entry)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            "Continue \(entry.title), \(entry.progressPercent) percent watched"
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func continueWatchingCard(
        _ entry: PlaybackHistoryEntry
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                KinetiqPalette.blue,
                                KinetiqPalette.violet,
                                KinetiqPalette.cyan.opacity(0.85)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Circle()
                    .stroke(.white.opacity(0.17), lineWidth: 1)
                    .frame(width: 105, height: 105)
                    .offset(x: 125, y: -10)

                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(.white.opacity(0.88))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack {
                    Label(
                        "\(entry.progressPercent)%",
                        systemImage: "play.fill"
                    )
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.28), in: Capsule())

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(10)
            }
            .frame(width: 224, height: 112)
            .clipShape(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(entry.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack {
                    Text("\(entry.progressPercent)% watched")
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 6)

                    Text("\(entry.remainingTimeText) left")
                        .foregroundStyle(KinetiqPalette.accent)
                }
                .font(.system(size: 10, weight: .semibold))

                ProgressView(value: entry.progress)
                    .tint(KinetiqPalette.accent)
            }
            .padding(.horizontal, 2)
        }
        .frame(width: 224, alignment: .leading)
        .contentShape(Rectangle())
    }

    // MARK: Library Entry

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionHeading(
                "Your library",
                detail: "YOUR PERSONAL COLLECTION"
            )

            Button(action: onOpenLibrary) {
                HStack(spacing: 14) {
                    Image(systemName: "play.rectangle.on.rectangle.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(KinetiqPalette.accent)
                        .frame(width: 48, height: 48)
                        .background(
                            KinetiqPalette.accent.opacity(0.12),
                            in: RoundedRectangle(
                                cornerRadius: 15,
                                style: .continuous
                            )
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Open your library")
                            .font(
                                .system(
                                    size: 14,
                                    weight: .bold,
                                    design: .rounded
                                )
                            )
                            .foregroundStyle(.primary)

                        Text("Browse and play your imported videos")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(15)
                .background(
                    Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(
                        cornerRadius: 20,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 20,
                        style: .continuous
                    )
                    .strokeBorder(
                        Color.primary.opacity(0.045),
                        lineWidth: 0.7
                    )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open your local video library")
        }
    }

    // MARK: Manga Placeholder

    private var mangaPlaceholder: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("A NEW WAY TO READ.")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(2.3)
                    .foregroundStyle(KinetiqPalette.accent)

                Text("Your manga universe.")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .tracking(-1.1)
                    .fixedSize(horizontal: false, vertical: true)

                Text(
                    "Discover, organize and read manga from the sources you choose."
                )
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            }

            ZStack {
                RoundedRectangle(
                    cornerRadius: 27,
                    style: .continuous
                )
                .fill(
                    LinearGradient(
                        colors: [
                            KinetiqPalette.violet.opacity(0.20),
                            KinetiqPalette.blue.opacity(0.12),
                            Color(uiColor: .secondarySystemGroupedBackground)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

                Circle()
                    .fill(KinetiqPalette.violet.opacity(0.12))
                    .frame(width: 190, height: 190)
                    .blur(radius: 3)
                    .offset(x: 105, y: -50)

                VStack(spacing: 14) {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 57, weight: .light))
                        .foregroundStyle(KinetiqPalette.violet)

                    Text("Manga is taking shape")
                        .font(
                            .system(
                                size: 18,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(.primary)

                    Text(
                        "The manga library, source integration and reader will be built here."
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 260)
                }
                .padding(25)
            }
            .frame(height: 260)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 27,
                    style: .continuous
                )
            )
        }
        .padding(.top, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .entrance(appeared, delay: 0.05)
    }

    // MARK: Shared Section Heading

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

// MARK: - Discover Screen

struct DiscoverView: View {
    private let categories = [
        "All", "Movies", "Series", "Anime", "Manga"
    ]

    @State private var selectedCategory = "All"
    @State private var appeared = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 27) {
                header
                    .entrance(appeared, delay: 0.02)

                introduction
                    .entrance(appeared, delay: 0.08)

                categorySection
                    .entrance(appeared, delay: 0.14)

                discoveryPlaceholder
                    .entrance(appeared, delay: 0.20)
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

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image("KinetiqLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 50, height: 50)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 16,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("KINETIQ")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .tracking(2.2)

                Text("SEARCH & DISCOVER")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: Introduction

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("FIND YOUR NEXT FAVOURITE.")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(2.4)
                .foregroundStyle(KinetiqPalette.accent)

            Text("A universe to explore.")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .tracking(-1.25)
                .fixedSize(horizontal: false, vertical: true)

            Text(
                "Movies, series, anime and manga. Choose what you feel like exploring."
            )
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    // MARK: Categories

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                Text("Explore your way")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .tracking(-0.35)

                Spacer(minLength: 8)

                Text("THE WHOLE UNIVERSE")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { category in
                        Button {
                            withAnimation(
                                .spring(
                                    response: 0.32,
                                    dampingFraction: 0.78
                                )
                            ) {
                                selectedCategory = category
                            }
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
                                        : Color(
                                            uiColor: .secondarySystemGroupedBackground
                                        ),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(
                            selectedCategory == category ? .isSelected : []
                        )
                    }
                }
            }
        }
    }

    // MARK: Discovery Placeholder

    private var discoveryPlaceholder: some View {
        VStack(alignment: .leading, spacing: 15) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 31, weight: .light))
                .foregroundStyle(KinetiqPalette.accent)
                .frame(width: 58, height: 58)
                .background(
                    KinetiqPalette.accent.opacity(0.12),
                    in: RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(
                    selectedCategory == "All"
                        ? "Your next story starts here."
                        : "Explore \(selectedCategory.lowercased())."
                )
                .font(.system(size: 18, weight: .bold, design: .rounded))

                Text(
                    "Your catalogue will appear here as Kinetiq connects to content sources."
                )
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 23, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .strokeBorder(
                    Color.primary.opacity(0.045),
                    lineWidth: 0.7
                )
        }
    }
}

// MARK: - Entrance Animation

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