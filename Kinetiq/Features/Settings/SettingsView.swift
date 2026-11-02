
import SwiftUI

struct SettingsView: View {
    @AppStorage(AppStorageKey.appearance)
    private var appearanceRawValue = AppAppearance.system.rawValue

    @State private var showingWhatsNew = false

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearanceRawValue) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("What's New") {
                    Button {
                        showingWhatsNew = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles.rectangle.stack")
                                .font(.title3)
                                .foregroundStyle(KinetiqPalette.cyan)
                                .frame(width: 38, height: 38)
                                .background(
                                    KinetiqPalette.cyan.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 12)
                                )

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Update Log")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)

                                Text("See what's new in Kinetiq")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text("v\(version)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Section("About Kinetiq") {
                    LabeledContent("Version", value: version)
                    LabeledContent("Platform", value: "iOS")
                    LabeledContent("Distribution", value: "Sideload")
                }

                Section("The idea") {
                    Text("Your Streams, Your Modules, Your Rules.")
                        .font(.system(.body, design: .rounded).weight(.semibold))

                    Text("Kinetiq is being built as a fluid, modular media experience.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingWhatsNew) {
                WhatsNewView()
            }
        }
    }
}

// MARK: - What's New

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var appeared = false

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0"
    }

    private let updates: [(symbol: String, title: String, detail: String)] = [
        (
            "sparkles",
            "A refreshed Kinetiq identity",
            "A new visual direction, updated app icon and a more distinctive look."
        ),
        (
            "wand.and.stars",
            "Smoother interactions",
            "Refined navigation transitions, animations and interactive details."
        ),
        (
            "square.grid.2x2",
            "A stronger foundation",
            "The app structure is being prepared for a unified movies, series, anime and manga experience."
        ),
        (
            "slider.horizontal.3",
            "More control",
            "Appearance settings and a dedicated place to revisit update notes."
        )
    ]

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    header

                    VStack(alignment: .leading, spacing: 8) {
                        Text("A NEW CHAPTER")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(2.5)
                            .foregroundStyle(KinetiqPalette.cyan)

                        Text("What's New")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .tracking(-1.2)

                        Text("Here's what changed in Kinetiq.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 12) {
                        ForEach(Array(updates.enumerated()), id: \.offset) { index, update in
                            updateRow(update)
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 14)
                                .animation(
                                    reduceMotion
                                    ? nil
                                    : .spring(response: 0.48, dampingFraction: 0.84)
                                        .delay(Double(index) * 0.07),
                                    value: appeared
                                )
                        }
                    }

                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Text("Continue to Kinetiq")
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background {
                            LinearGradient(
                                colors: [
                                    KinetiqPalette.cyan,
                                    KinetiqPalette.blue,
                                    KinetiqPalette.violet
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)

                    Text("KINETIQ  •  YOUR MEDIA UNIVERSE")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1.8)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
                .padding(24)
            }
        }
        .preferredColorScheme(nil)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5)) {
                appeared = true
            }
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 9) {
                Image(systemName: "waveform")
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background {
                        LinearGradient(
                            colors: [KinetiqPalette.cyan, KinetiqPalette.violet],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Text("KINETIQ")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .tracking(2)
            }

            Spacer()

            Text("VERSION \(version)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())
        }
    }

    private func updateRow(
        _ update: (symbol: String, title: String, detail: String)
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: update.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(KinetiqPalette.cyan)
                .frame(width: 44, height: 44)
                .background(
                    KinetiqPalette.cyan.opacity(0.11),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(update.title)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))

                Text(update.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
            }

            Spacer(minLength: 0)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 19, style: .continuous)
        )
    }
}