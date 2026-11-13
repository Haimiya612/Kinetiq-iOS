import SwiftUI

// MARK: - Unified visual layer
//
// The renderer is deliberately independent of AVPlayer and module/networking
// objects. Local and remote playback adapters both drive this same interface.
// Every visible action is forwarded to the active playback engine.

@MainActor
struct KinetiqUnifiedPlayerChrome: View {
    struct Panel: Identifiable {
        let id: String
        let symbol: String
        let selected: Bool
    }

    @AppStorage(KinetiqVisualTheme.storageKey)
    private var themeRaw = KinetiqVisualTheme.signature.rawValue
    private var theme: KinetiqVisualTheme {
        KinetiqVisualTheme(rawValue: themeRaw) ?? .signature
    }
    private var playerAccent: Color {
        theme == .signature ? KinetiqPalette.cyan : theme.accent
    }
    let safeAreaInsets: EdgeInsets
    let title: String
    let playing: Bool
    let busy: Bool
    let aspectFill: Bool
    let pictureInPictureAvailable: Bool
    let displayedTime: Double
    let duration: Double
    let elapsedLabel: String
    let durationLabel: String
    let panels: [Panel]
    let airPlayControl: AnyView

    let onClose: () -> Void
    let onStartPictureInPicture: () -> Void
    let onToggleAspect: () -> Void
    let onPrevious: () -> Void
    let onRewind: () -> Void
    let onTogglePlay: () -> Void
    let onForward: () -> Void
    let onNext: () -> Void
    let onSeekChanged: (Double) -> Void
    let onSeekEditingChanged: (Bool) -> Void
    let onPanelSelected: (String) -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.58), location: 0),
                    .init(color: .clear, location: 0.27),
                    .init(color: .clear, location: 0.60),
                    .init(color: .black.opacity(0.70), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                header
                    .padding(.top, max(safeAreaInsets.top, 14))
                Spacer(minLength: 18)
                transport
                Spacer(minLength: 18)
                footer
                    .padding(.bottom, max(safeAreaInsets.bottom, 15))
            }
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 11) {
            headerButton("chevron.down", label: "Close player", size: 15, action: onClose)
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(theme.isEditorial ? "NOW SHOWING" :
                     theme.isEnergetic ? "THE NEXT EPISODE" :
                     theme.isQuiet ? "FOCUS MODE" :
                     theme.isAtmospheric ? "YOUR STREAM" : "NOW PLAYING")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.8)
                    .foregroundStyle(playerAccent)

                Text(title)
                    .font(.system(size: theme.isEditorial ? 16 : 14,
                                  weight: .semibold,
                                  design: theme.preferredFontDesign))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            airPlayControl
                .frame(width: 40, height: 40)
                .background {
                    if theme.isEditorial || theme.isQuiet {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(.black.opacity(0.68))
                    } else {
                        Circle().fill(.black.opacity(0.34))
                    }
                }
                .overlay {
                    if theme.isEnergetic {
                        Circle().strokeBorder(playerAccent.opacity(0.5), lineWidth: 1)
                    }
                }
                .accessibilityLabel("AirPlay")

            if pictureInPictureAvailable {
                headerButton("pip", label: "Start Picture in Picture", size: 15, action: onStartPictureInPicture)
            }

            headerButton(
                aspectFill
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right",
                label: aspectFill ? "Fit video to screen" : "Fill screen with video",
                size: 14,
                action: onToggleAspect
            )
        }
    }

    private func headerButton(
        _ symbol: String,
        label: String,
        size: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background {
                    if theme.isEditorial || theme.isQuiet {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(.black.opacity(0.68))
                    } else {
                        Circle().fill(.black.opacity(0.34))
                    }
                }
                .overlay {
                    if theme.isEnergetic {
                        Circle().strokeBorder(playerAccent.opacity(0.5), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var transport: some View {
        HStack(spacing: 13) {
            transportButton("backward.end.fill", size: 18, width: 38,
                            label: "Previous", action: onPrevious)
            transportButton("gobackward.10", size: 25, width: 44,
                            label: "Back 10 seconds", action: onRewind)

            Button(action: onTogglePlay) {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: theme.isQuiet ? 64 : 72,
                           height: theme.isQuiet ? 64 : 72)
                    .background {
                        if theme.isEditorial {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.black.opacity(0.82))
                        } else if theme.isEnergetic || theme.isAtmospheric {
                            Circle().fill(LinearGradient(colors: [
                                theme.accent.opacity(0.86),
                                theme.highlight.opacity(0.77)
                            ], startPoint: .topLeading, endPoint: .bottomTrailing))
                        } else if theme == .nocturne {
                            Circle().fill(.black.opacity(0.66))
                        } else {
                            Circle().fill(.ultraThinMaterial)
                        }
                    }
                    .overlay {
                        if theme.isEditorial {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                        } else {
                            Circle().strokeBorder(playerAccent.opacity(
                                theme == .anime ? 0.85 : 0.22
                            ), lineWidth: theme == .anime ? 2 : 1)
                        }
                    }
                    .shadow(color: .black.opacity(0.28), radius: 18, y: 7)
            }
            .accessibilityLabel(playing ? "Pause" : "Play")

            transportButton("goforward.10", size: 25, width: 44,
                            label: "Forward 10 seconds", action: onForward)
            transportButton("forward.end.fill", size: 18, width: 38,
                            label: "Next", action: onNext)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .opacity(busy ? 0.55 : 1)
    }

    private func transportButton(
        _ symbol: String,
        size: CGFloat,
        width: CGFloat,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: width, height: 58)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { min(max(displayedTime.isFinite ? displayedTime : 0, 0), max(duration, 1)) },
                        set: { onSeekChanged($0) }
                    ),
                    in: 0...max(duration.isFinite ? duration : 1, 1),
                    onEditingChanged: onSeekEditingChanged
                )
                .tint(playerAccent)
                .accessibilityLabel("Playback position")

                HStack {
                    Text(elapsedLabel)
                    Spacer()
                    Text(durationLabel)
                }
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.88))
            }

            panelBar
        }
    }

    private var panelBar: some View {
        HStack(spacing: 1) {
            ForEach(panels) { panel in
                Button {
                    onPanelSelected(panel.id)
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: panel.symbol)
                            .font(.system(size: 15, weight: .semibold))
                        Text(panel.id)
                            .font(.system(size: 8, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .foregroundStyle(
                        panel.selected
                            ? playerAccent
                            : .white.opacity(theme == .nocturne ? 0.72 : 0.92)
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(panel.id)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 5)
        .background {
            if theme.isEditorial || theme.isQuiet {
                RoundedRectangle(cornerRadius: theme == .cinema ? 8 : 14)
                    .fill(.black.opacity(theme == .nocturne ? 0.87 : 0.77))
            } else if theme.isEnergetic || theme.isAtmospheric {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(playerAccent.opacity(0.44), lineWidth: 1)
                    }
            } else {
                Capsule().fill(.ultraThinMaterial)
            }
        }
        .overlay {
            if theme.isEditorial || theme.isQuiet {
                RoundedRectangle(cornerRadius: theme == .cinema ? 8 : 14)
                    .strokeBorder(.white.opacity(theme == .cinema ? 0.24 : 0.08), lineWidth: 1)
            }
        }
        .shadow(color: .black.opacity(0.22), radius: theme == .nocturne ? 5 : 16, y: 6)
    }
}

// MARK: - Shared options-sheet frame

@MainActor
struct KinetiqUnifiedPlayerOptionsFrame<Content: View>: View {
    let title: String
    let symbol: String
    let onClose: () -> Void
    @ViewBuilder let content: Content

    init(
        title: String,
        symbol: String,
        onClose: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbol = symbol
        self.onClose = onClose
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.white.opacity(0.35))
                .frame(width: 38, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 16)

            HStack {
                HStack(spacing: 10) {
                    Image(systemName: symbol)
                        .foregroundStyle(KinetiqPalette.cyan)
                    Text(title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 32, height: 32)
                        .background(.white.opacity(0.10), in: Circle())
                }
                .accessibilityLabel("Close options")
            }
            .padding(.horizontal, 19)
            .padding(.bottom, 14)

            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    content
                }
                .padding(18)
            }
            .frame(maxHeight: 390)
        }
        .background(.ultraThinMaterial)
        .background(Color(red: 0.035, green: 0.045, blue: 0.065).opacity(0.90))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24)
                .stroke(.white.opacity(0.13), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.32), radius: 25, y: -5)
    }
}

// MARK: - Shared playback error presentation

@MainActor
struct KinetiqUnifiedPlayerFailureOverlay: View {
    let message: String
    let onRetry: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.orange)

            Text("Playback issue")
                .font(.headline)
                .foregroundStyle(.white)

            Text(message)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                Button(action: onRetry) {
                    Label("Try again", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(KinetiqPalette.cyan, in: Capsule())
                }
                Button(action: onSkip) {
                    Label("Skip", systemImage: "forward.end.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(.white.opacity(0.13), in: Capsule())
                }
            }
            .padding(.top, 5)
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20)
            .stroke(.white.opacity(0.12), lineWidth: 1))
        .padding(30)
    }
}