// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import SwiftUI
import AppKit

struct BrowserPane: View {
    @Environment(AppState.self) private var state

    // Density-m default per the prototype: 2 columns, 8px gap.
    private let columns = [
        GridItem(.flexible(minimum: 80), spacing: 8, alignment: .center),
        GridItem(.flexible(minimum: 80), spacing: 8, alignment: .center),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if state.folderURL == nil {
                placeholder("No folder open")
            } else if state.library.isEmpty && !state.isScanning {
                placeholder("No images in this folder")
            } else if state.filter.isActive && state.visibleLibrary.isEmpty {
                placeholder("No files match the filter")
            } else {
                grid
            }
        }
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(state.visibleLibrary) { entry in
                        ThumbnailCell(
                            entry: entry,
                            isSelected: !state.batchMode && state.selectedID == entry.id,
                            batchIndex: batchIndex(for: entry.id),
                            cache: state.thumbs
                        )
                        .onTapGesture {
                            let mods = NSEvent.modifierFlags
                            if mods.contains(.shift) {
                                state.selectRange(to: entry.id)
                            } else if mods.contains(.command) {
                                state.toggleBatch(entry.id)
                            } else {
                                state.select(entry.id)
                            }
                        }
                    }
                }
                .padding(8)
            }
            // Keep the selected thumbnail on-screen. Reveals the restored
            // selection at launch (it can be far down a large folder) and
            // follows arrow-key navigation to the grid edges. scrollTo with a
            // nil anchor moves the minimum distance and no-ops when the cell is
            // already fully visible, so ordinary clicks don't jump the grid.
            // initial: true fires once on appear for a selection already set.
            .onChange(of: state.selectedID, initial: true) { _, id in
                guard let id else { return }
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        proxy.scrollTo(id)
                    }
                }
            }
        }
    }

    private func batchIndex(for id: String) -> Int? {
        guard state.batchMode else { return nil }
        return state.batchOrder.firstIndex(of: id).map { $0 + 1 }
    }

    private func placeholder(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 11 * 1.15))
                .foregroundStyle(Theme.fgFaint)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
