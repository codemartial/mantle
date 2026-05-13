import SwiftUI

// Read-only chip list for the design pass. Editable input + commit
// behaviour wires up in the editable-bindings step.

struct KeywordChips: View {
    let keywords: [String]
    var placeholder: String = "Add keyword..."

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Keywords")

            FlowLayout(spacing: 4) {
                ForEach(Array(keywords.enumerated()), id: \.offset) { _, kw in
                    chip(kw)
                }
                placeholderChip
            }
            .padding(5)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .topLeading)
            .background(Theme.bgInput)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Theme.line1, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }

    @ViewBuilder
    private func chip(_ text: String) -> some View {
        HStack(spacing: 2) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 6, height: 6)
                .padding(.leading, 5)
            Text(text)
                .font(.system(size: 11 * 1.15))
                .foregroundStyle(Theme.fg)
                .padding(.trailing, 6)
        }
        .frame(height: 18)
        .background(Theme.chipBg)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Theme.chipBorder, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var placeholderChip: some View {
        Text(placeholder)
            .font(.system(size: 11 * 1.15))
            .foregroundStyle(Theme.fgFaint)
            .padding(.horizontal, 6)
            .frame(height: 18)
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
