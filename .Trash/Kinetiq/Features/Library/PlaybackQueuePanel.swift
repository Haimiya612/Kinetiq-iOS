import SwiftUI

struct PlaybackQueuePanel: View {
    @ObservedObject var queue: PlaybackQueueStore

    let onSelect: (PlaybackQueueEntry) -> Void
    let onRemove: (PlaybackQueueEntry) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.white.opacity(0.3))
                .frame(width: 38, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 17)

            header

            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let current = queue.currentEntry {
                        sectionTitle("NOW PLAYING")
                        currentRow(current)
                    }

                    if !queue.upcomingEntries.isEmpty {
                        sectionTitle("UP NEXT")
                        VStack(spacing: 8) {
                            ForEach(queue.upcomingEntries) { entry in
                                queueRow(entry)
                            }
                        }
                    }

                    let previousEntries = previousItems
                    if !previousEntries.isEmpty {
                        sectionTitle("PLAYED")
                        VStack(spacing: 8) {
                            ForEach(previousEntries) { entry in
                                playedRow(entry)
                            }
                        }
                    }

                    if queue.isEmpty {
                        emptyState
                    }
                }
                .padding(18)
            }
            .frame(maxHeight: 420)

            footer
        }
        .background(.ultraThinMaterial)
        .background(Color(red: 0.035, green: 0.045, blue: 0.065).opacity(0.96))
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 24,
                topTrailingRadius: 24
            )
        )
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(
                topLeadingRadius: 24,
                topTrailingRadius: 24
            )
            .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Up Next")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("\(queue.entries.count) videos in queue")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 32, height: 32)
                    .background(.white.opacity(0.1), in: Circle())
            }
            .accessibilityLabel("Close queue")
        }
        .padding(.horizontal, 19)
        .padding(.bottom, 15)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                queue.toggleShuffle()
            } label: {
                Label("Shuffle", systemImage: "shuffle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(queue.isShuffled ? KinetiqPalette.cyan : .white.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        queue.isShuffled ? KinetiqPalette.cyan.opacity(0.14) : .white.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
            }
            .buttonStyle(.plain)

            Button {
                queue.cycleRepeatMode()
            } label: {
                Label(queue.repeatMode.title, systemImage: queue.repeatMode.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(queue.repeatMode == .off ? .white.opacity(0.75) : KinetiqPalette.cyan)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        queue.repeatMode == .off ? .white.opacity(0.07) : KinetiqPalette.cyan.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 18)
    }

    private var emptyState: some View {
        VStack(spacing: 11) {
            Image(systemName: "text.badge.plus")
                .font(.system(size: 29, weight: .light))
                .foregroundStyle(KinetiqPalette.cyan)

            Text("Your queue is empty")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)

            Text("Add videos from your library to build your queue.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 35)
    }

    private var previousItems: [PlaybackQueueEntry] {
        guard queue.currentIndex > 0 else { return [] }
        return Array(queue.entries.prefix(queue.currentIndex).reversed())
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(1.4)
            .foregroundStyle(KinetiqPalette.cyan)
    }

    private func currentRow(_ entry: PlaybackQueueEntry) -> some View {
        HStack(spacing: 12) {
            artwork

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Label("Playing now", systemImage: "waveform")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(KinetiqPalette.cyan)
            }

            Spacer()

            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 14))
                .foregroundStyle(KinetiqPalette.cyan)
        }
        .padding(11)
        .background(KinetiqPalette.cyan.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(KinetiqPalette.cyan.opacity(0.22), lineWidth: 1)
        }
    }

    private func queueRow(_ entry: PlaybackQueueEntry) -> some View {
        HStack(spacing: 10) {
            Button {
                onSelect(entry)
            } label: {
                HStack(spacing: 11) {
                    artwork

                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        Text("Queued")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.45))
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "play.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(KinetiqPalette.cyan)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                onRemove(entry)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 30, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(entry.title) from queue")
        }
        .padding(9)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
    }

    private func playedRow(_ entry: PlaybackQueueEntry) -> some View {
        Button {
            onSelect(entry)
        } label: {
            HStack(spacing: 11) {
                artwork.opacity(0.55)

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)

                    Text("Previously played")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                }

                Spacer()

                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(9)
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(
                    LinearGradient(
                        colors: [KinetiqPalette.cyan.opacity(0.24), KinetiqPalette.violet.opacity(0.24)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: "play.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(KinetiqPalette.cyan)
        }
        .frame(width: 43, height: 43)
    }
}
