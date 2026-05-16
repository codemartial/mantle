import SwiftUI

// Chip list with an inline draft input. Comma or Enter commits. Backspace
// on an empty draft removes the last chip. Each chip carries an X to remove.
// Design pass: local @State seeded from EditStore on selection change.
// Lowercases + de-dupes on commit, matching app.jsx KeywordChips.

struct KeywordChips: View {
    @Environment(AppState.self) private var state

    @State private var keywords: [String] = []
    @State private var draft: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Keywords") {
                Text(String(keywords.count))
                    .font(.system(size: 10 * 1.15, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
            }

            FlowLayout(spacing: 4) {
                ForEach(Array(keywords.enumerated()), id: \.offset) { index, kw in
                    chip(kw, at: index)
                }
                draftInput
            }
            .padding(5)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .topLeading)
            .background(Theme.bgInput)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(inputFocused ? Theme.accentEdge : Theme.line1,
                                  lineWidth: inputFocused ? 1 : 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
            .onTapGesture { inputFocused = true }
        }
        .onAppear { seedFromRecord() }
        .onChange(of: state.selectedRecord?.id ?? "") { _, _ in seedFromRecord() }
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
                keywords.remove(at: index)
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

    // MARK: - Draft input

    private var draftInput: some View {
        TextField(keywords.isEmpty ? "Type a keyword, press , to add" : "Add...",
                  text: $draft)
            .textFieldStyle(.plain)
            .focused($inputFocused)
            .font(.system(size: 11 * 1.15))
            .foregroundStyle(Theme.fg)
            .frame(minWidth: 80, idealWidth: 120, maxWidth: .infinity, minHeight: 18)
            .padding(.horizontal, 4)
            .onSubmit { commit(draft) }
            .onChange(of: draft) { _, newValue in
                if newValue.contains(",") { commit(newValue) }
            }
            .onKeyPress(.delete) {
                if draft.isEmpty, !keywords.isEmpty {
                    keywords.removeLast()
                    return .handled
                }
                return .ignored
            }
    }

    // MARK: - Commit / seed

    private func commit(_ raw: String) {
        let parts = raw
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { draft = ""; return }
        for part in parts where !keywords.contains(part) {
            keywords.append(part)
        }
        draft = ""
    }

    private func seedFromRecord() {
        keywords = state.selectedRecord?.keywords ?? []
        draft = ""
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
