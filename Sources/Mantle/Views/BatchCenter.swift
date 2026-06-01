// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import SwiftUI

// Replaces PreviewPane while in batch mode. Shows a stack of up to three
// thumbnails (master on top, others fanned behind) and a label naming the
// master. The center pane is otherwise too big for a single-image preview
// to make sense in batch mode.

struct BatchCenter: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                let cards = stackEntries
                ForEach(Array(cards.enumerated()), id: \.element.id) { idx, entry in
                    let isMaster = idx == cards.count - 1   // last in DOM = on top
                    let offset = CGFloat(cards.count - 1 - idx)
                    BatchCard(entry: entry, cache: state.thumbs, isMaster: isMaster)
                        .offset(x: -offset * 16, y: -offset * 8)
                        .rotationEffect(.degrees(isMaster ? 0 : Double(offset) * -3))
                        .zIndex(Double(idx))
                }
            }
            .frame(maxWidth: .infinity)

            Text(label)
                .font(.system(size: 11 * 1.15))
                .foregroundStyle(Theme.fgMute)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .lineLimit(2)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Top of the visual stack = master = last in the ZStack's children list.
    // Take up to 3, with master last so it draws on top.
    private var stackEntries: [LibraryEntry] {
        let ids = state.batchOrder.prefix(3)
        let entries = ids.compactMap { id in
            state.library.first(where: { $0.id == id })
        }
        return Array(entries.reversed())
    }

    private var label: String {
        let n = state.batchOrder.count
        let masterName = state.library.first { $0.id == state.masterID }?.basename ?? ""
        if masterName.isEmpty {
            return "\(n) images selected -- master values prefill the editors below."
        }
        return "\(n) images selected, master is \(masterName) -- its values prefill the editors below."
    }
}

private struct BatchCard: View {
    let entry: LibraryEntry
    let cache: ThumbnailCache
    let isMaster: Bool

    @State private var image: NSImage?

    private let side: CGFloat = 220

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                } else {
                    Theme.bgThumb
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if isMaster {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 6, height: 6)
                    Text("MASTER")
                        .font(.system(size: 9 * 1.15, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.black.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(8)
            }
        }
        .frame(width: side, height: side)
        .background(Theme.bgPanel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isMaster ? Theme.accent : Theme.line2,
                              lineWidth: isMaster ? 1.5 : 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
        .task(id: entry.displayURL) {
            let loaded = await cache.requestThumbnail(for: entry.displayURL, side: side)
            if !Task.isCancelled {
                image = loaded
            }
        }
    }
}
