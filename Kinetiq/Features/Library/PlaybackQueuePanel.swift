import SwiftUI

struct PlaybackQueuePanel: View {
    @ObservedObject var queue: PlaybackQueueStore

    let onSelect: (PlaybackQueueEntry) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.white.opacity(0.35))
                .frame(width: 38, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 16)

            header

            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(height: 1)

            if queue.isEmpty {
                emptyState
            } else {
                queueList
            }

            footer
        }
        .background(.ultraThinMaterial)
        .background(
            Color(
                red: 0.035,
                green: 0.045,
                blue: 0.065
            ).opacity(0.94)
        )
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
            .stroke(.white.opacity(0.13), lineWidth: 1)
        }
        .shadow(
            color: .black.opacity(0.32),
            radius: 25,
            y: -5
        )
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "list.bullet")
                .foregroundStyle(KinetiqPalette.cyan)

            VStack(alignment: .leading, spacing: 3) {
                Text("Up Next")
                    .font(
                        .system(
                            size: 17,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.white)

                Text(
                    "\(queue.entries.count) videos in queue"
                )
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.48))
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 32, height: 32)
                    .background(
                        .white.opacity(0.10),
                        in: Circle()
                    )
            }
            .accessibilityLabel("Close queue")
        }
        .padding(.horizontal, 19)
        .padding(.bottom, 14)
    }

    private var queueList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if let current = queue.currentEntry {
                    queueRow(
                        current,
                        position: queue.currentIndex,
                        isCurrent: true
                    )
                }

                if !queue.upcomingEntries.isEmpty {
                    HStack {
                        Text("UP NEXT")
                            .font(
                                .system(
                                    size: 9,
                                    weight: .bold,
                                    design: .rounded
                                )
                            )
                            .tracking(1.5)
                            .foregroundStyle(
                                .white.opacity(0.42)
                            )

                        Spacer()
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 3)

                    ForEach(
                        Array(
                            queue.upcomingEntries.enumerated()
                        ),
                        id: \.element.id
                    ) { index, entry in
                        queueRow(
                            entry,
                            position: queue.currentIndex + index + 1,
                            isCurrent: false
                        )
                    }
                }

                if queue.currentIndex > 0 {
                    HStack {
                        Text("PLAYED")
                            .font(
                                .system(
                                    size: 9,
                                    weight: .bold,
                                    design: .rounded
                                )
                            )
                            .tracking(1.5)
                            .foregroundStyle(
                                .white.opacity(0.42)
                            )

                        Spacer()
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 3)

                    ForEach(
                        Array(
                            queue.entries.prefix(queue.currentIndex)
                        )
                    ) { entry in
                        queueRow(
                            entry,
                            position: queue.entries.firstIndex(
                                where: { $0.id == entry.id }
                            ) ?? 0,
                            isCurrent: false
                        )
                        .opacity(0.48)
                    }
                }
            }
            .padding(16)
        }
        .frame(maxHeight: 330)
    }

    private func queueRow(
        _ entry: PlaybackQueueEntry,
        position: Int,
        isCurrent: Bool
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        isCurrent
                            ? KinetiqPalette.cyan.opacity(0.16)
                            : .white.opacity(0.07)
                    )

                Image(
                    systemName: isCurrent
                        ? "waveform"
                        : "play.fill"
                )
                .font(
                    .system(
                        size: isCurrent ? 15 : 12,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    isCurrent
                        ? KinetiqPalette.cyan
                        : .white.opacity(0.62)
                )
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(
                        .system(
                            size: 12,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(
                    isCurrent
                        ? "NOW PLAYING"
                        : entry.fileURL.pathExtension.uppercased()
                )
                .font(
                    .system(
                        size: 9,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .tracking(0.8)
                .foregroundStyle(
                    isCurrent
                        ? KinetiqPalette.cyan
                        : .white.opacity(0.42)
                )
            }

            Spacer(minLength: 4)

            if isCurrent {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(KinetiqPalette.cyan)
            } else {
                Button {
                    queue.remove(mediaID: entry.id)
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 17))
                        .foregroundStyle(
                            .white.opacity(0.48)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "Remove \(entry.title) from queue"
                )
            }
        }
        .padding(10)
        .background(
            isCurrent
                ? KinetiqPalette.cyan.opacity(0.10)
                : .white.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 13)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(
                    isCurrent
                        ? KinetiqPalette.cyan.opacity(0.24)
                        : .clear,
                    lineWidth: 1
                )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isCurrent else { return }
            onSelect(entry)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.badge.plus")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(KinetiqPalette.cyan)

            Text("Your queue is empty")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)

            Text("Add videos from your library to play them next.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.52))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 35)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                queue.toggleShuffle()
            } label: {
                Label(
                    "Shuffle",
                    systemImage: "shuffle"
                )
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(
                    queue.isShuffled
                        ? KinetiqPalette.cyan
                        : .white.opacity(0.72)
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    .white.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 12)
                )
            }
            .buttonStyle(.plain)

            Button {
                queue.cycleRepeatMode()
            } label: {
                Label(
                    queue.repeatMode.title,
                    systemImage: queue.repeatMode.symbol
                )
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(
                    queue.repeatMode == .off
                        ? .white.opacity(0.72)
                        : KinetiqPalette.cyan
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    .white.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 12)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }
}