
import SwiftUI
import UIKit

// MARK: - Tab Navigation

private enum KinetiqTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case discover = "Discover"
    case library = "Library"
    case modules = "Modules"
    case profile = "Profile"

    var id: String { rawValue }

    var index: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .discover: "safari"
        case .library: "books.vertical.fill"
        case .modules: "square.stack.3d.up.fill"
        case .profile: "person.crop.circle"
        }
    }
}

private enum TabNavigationDirection {
    case forward
    case backward

    var insertionEdge: Edge {
        self == .forward ? .trailing : .leading
    }

    var removalEdge: Edge {
        self == .forward ? .leading : .trailing
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    let tagline: String

    // Keep the existing storage key so saved preferences are preserved.
    @AppStorage("kinetiq.appearance.liquidGlassButtons")
    private var useLiquidGlassDock = false

    @State private var selectedTab: KinetiqTab = .home
    @State private var navigationDirection: TabNavigationDirection = .forward
    @State private var requestedMediaID: String?

    @StateObject private var playbackHistory = PlaybackHistoryStore.shared

    @Namespace private var tabAnimation

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        mainLayout
    }

    private var mainLayout: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case .home:
                    HomeView(
                        tagline: tagline,
                        continueWatching: playbackHistory.continueWatching,
                        onDiscover: {
                            select(.discover)
                        },
                        onModules: {
                            select(.modules)
                        },
                        onContinueWatching: { entry in
                            openContinueWatching(entry)
                        }
                    )

                case .discover:
                    DiscoverView()

                case .library:
                    LibraryView(
                        requestedMediaID: $requestedMediaID
                    )

                case .modules:
                    KinetiqPlaceholderView(
                        title: "Modules",
                        subtitle: "Connect sources and shape your Kinetiq experience.",
                        symbol: "square.stack.3d.up.fill",
                        accent: KinetiqPalette.violet
                    )

                case .profile:
                    NavigationStack {
                        KinetiqPlaceholderView(
                            title: "Your space",
                            subtitle: "Your preferences and personal Kinetiq experience.",
                            symbol: "person.crop.circle.fill",
                            accent: KinetiqPalette.blue
                        )
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                NavigationLink {
                                    SettingsView()
                                } label: {
                                    Image(systemName: "gearshape")
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(selectedTab)
            .transition(contentTransition)

            bottomBar
        }
        .background(Color(uiColor: .systemBackground))
        .tint(KinetiqPalette.accent)
    }

    // MARK: Continue Watching Routing

    private func openContinueWatching(
        _ entry: PlaybackHistoryEntry
    ) {
        requestedMediaID = entry.id
        select(.library)
    }

    // MARK: Content Transition

    private var contentTransition: AnyTransition {
        guard !reduceMotion else {
            return .opacity
        }

        return .asymmetric(
            insertion: .move(edge: navigationDirection.insertionEdge)
                .combined(with: .opacity),
            removal: .move(edge: navigationDirection.removalEdge)
                .combined(with: .opacity)
        )
    }

    // MARK: Bottom Navigation

    private var bottomBar: some View {
        dockContent
            // The dock itself stays visually restrained.
            // Liquid Glass is reserved for the moving selected-tab indicator.
            .background(
                .regularMaterial,
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .strokeBorder(
                        Color.primary.opacity(0.08),
                        lineWidth: 0.7
                    )
            }
            .shadow(
                color: Color.black.opacity(0.07),
                radius: 14,
                x: 0,
                y: 5
            )
            .padding(.horizontal, 17)
            .padding(.top, 8)
            .padding(.bottom, 8)
    }

    private var dockContent: some View {
        HStack(spacing: 3) {
            ForEach(KinetiqTab.allCases) { tab in
                Button {
                    select(tab)
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 18, weight: .semibold))
                            .symbolEffect(
                                .bounce,
                                value: selectedTab == tab
                            )

                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(
                        selectedTab == tab
                            ? KinetiqPalette.accent
                            : Color.secondary
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 55)
                    .background {
                        if selectedTab == tab {
                            selectedTabIndicator
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(tab.rawValue)
                .accessibilityAddTraits(
                    selectedTab == tab ? .isSelected : []
                )
            }
        }
        .padding(6)
        // Swiping across the dock changes the selected destination.
        // The matched glass indicator follows the selected tab.
        .simultaneousGesture(
            DragGesture(minimumDistance: 32)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height

                    guard
                        abs(horizontal) > 45,
                        abs(horizontal) > abs(vertical)
                    else {
                        return
                    }

                    let nextIndex = selectedTab.index + (
                        horizontal < 0 ? 1 : -1
                    )

                    guard KinetiqTab.allCases.indices.contains(nextIndex) else {
                        return
                    }

                    select(KinetiqTab.allCases[nextIndex])
                }
        )
    }

    @ViewBuilder
    private var selectedTabIndicator: some View {
        if #available(iOS 26.0, *), useLiquidGlassDock {
            Capsule()
                .fill(.clear)
                .matchedGeometryEffect(
                    id: "active-tab",
                    in: tabAnimation
                )
                .glassEffect(
                    .regular.interactive(),
                    in: Capsule()
                )
        } else {
            Capsule()
                .fill(
                    KinetiqPalette.accent.opacity(0.15)
                )
                .matchedGeometryEffect(
                    id: "active-tab",
                    in: tabAnimation
                )
        }
    }

    // MARK: Selection

    private func select(_ tab: KinetiqTab) {
        guard selectedTab != tab else {
            return
        }

        navigationDirection = tab.index > selectedTab.index
            ? .forward
            : .backward

        withAnimation(
            reduceMotion
                ? .easeInOut(duration: 0.15)
                : .spring(response: 0.42, dampingFraction: 0.82)
        ) {
            selectedTab = tab
        }
    }
}

// MARK: - Placeholder Screens

private struct KinetiqPlaceholderView: View {
    let title: String
    let subtitle: String
    let symbol: String
    let accent: Color

    @State private var appeared = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
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

                    Text("KINETIQ")
                        .font(
                            .system(
                                size: 15,
                                weight: .black,
                                design: .rounded
                            )
                        )
                        .tracking(2)

                    Spacer()
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("YOUR MEDIA UNIVERSE")
                        .font(
                            .system(
                                size: 10,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .tracking(2)
                        .foregroundStyle(accent)

                    Text(title)
                        .font(
                            .system(
                                size: 37,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .tracking(-1.2)

                    Text(subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                }

                ZStack {
                    RoundedRectangle(
                        cornerRadius: 28,
                        style: .continuous
                    )
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(0.25),
                                accent.opacity(0.06),
                                Color(
                                    uiColor: .secondarySystemGroupedBackground
                                )
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                    Circle()
                        .fill(accent.opacity(0.12))
                        .frame(width: 190, height: 190)
                        .blur(radius: 2)
                        .offset(x: 100, y: -55)

                    Image(systemName: symbol)
                        .font(.system(size: 65, weight: .light))
                        .foregroundStyle(accent)
                        .scaleEffect(appeared ? 1 : 0.85)
                }
                .frame(height: 220)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 28,
                        style: .continuous
                    )
                )

                Text("A NEW CHAPTER IS TAKING SHAPE")
                    .font(
                        .system(
                            size: 9,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .tracking(1.6)
                    .foregroundStyle(.secondary)
            }
            .padding(22)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
        }
        .onAppear {
            withAnimation(
                .spring(response: 0.65, dampingFraction: 0.86)
            ) {
                appeared = true
            }
        }
    }
}