// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import SwiftUI

// Chip list with an inline draft input + keyword autocomplete (shared
// KeywordInputBox). Comma or Enter commits, a suggestion can be accepted with
// Enter / Tab / click, backspace on an empty draft removes the last chip,
// each chip carries an X to remove. Reads keywords directly from EditStore
// via AppState; mutations route through AppState.updateField so the dirty bit
// recomputes per change.

struct KeywordChips: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Keywords") {
                Text(String(keywords.count))
                    .font(.system(size: 10 * 1.15, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
            }

            KeywordInputBox(
                vocabulary: state.keywordVocabulary,
                existing: keywords,
                placeholder: keywords.isEmpty ? "Type a keyword, press , to add" : "Add...",
                onCommit: addKeyword,
                onBackspaceEmpty: removeLast
            ) {
                ForEach(Array(keywords.enumerated()), id: \.offset) { index, kw in
                    chip(kw, at: index)
                }
            }
            // Recreate the box (clearing its draft) when the selection changes.
            .id(state.selectedID)
        }
    }

    // MARK: - Source of truth

    private var keywords: [String] {
        state.selectedRecord?.keywords ?? []
    }

    // MARK: - Chip

    @ViewBuilder
    private func chip(_ text: String, at index: Int) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 5, height: 5)
                .padding(.leading, 6)
            Text(text)
                .font(.system(size: 11 * 1.15))
                .foregroundStyle(Theme.fg)
            Button {
                removeKeyword(at: index)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8 * 1.15, weight: .medium))
                    .foregroundStyle(Theme.fgDim)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(height: 18)
        .background(Theme.chipBg)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Theme.chipBorder, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Mutations

    // Add one keyword with exactly the given casing (canonical from a
    // suggestion, or the literal typed token). Case-insensitive dedupe at
    // add-time: typing "beach" when "Beach" is already present drops the new
    // one. To rename case, remove the existing chip first, then re-add. The
    // on-disk comparator stays case-sensitive (so loading ["Beach","beach"]
    // from someone else's sidecar doesn't get silently collapsed).
    private func addKeyword(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let id = state.selectedID else { return }
        state.updateField(id: id, field: .keywords) { record in
            let lower = t.lowercased()
            if !record.keywords.contains(where: { $0.lowercased() == lower }) {
                record.keywords.append(t)
            }
        }
    }

    private func removeLast() {
        guard !keywords.isEmpty else { return }
        removeKeyword(at: keywords.count - 1)
    }

    private func removeKeyword(at index: Int) {
        guard let id = state.selectedID else { return }
        state.updateField(id: id, field: .keywords) { record in
            guard index < record.keywords.count else { return }
            record.keywords.remove(at: index)
        }
    }
}

// Simple flow layout: wraps children to next row when they overflow.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + (rowWidth > 0 ? spacing : 0)
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)
        return CGSize(width: totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
