import SwiftUI

// Headline + caption editors anchored below the preview in the center pane.
// Labels sit ABOVE their inputs (not beside them, as the JSX did) so the
// input fields can use the full center-pane width -- the Swift app's left
// and right columns are wider than the JSX prototype's, which left only a
// narrow strip for the inputs when the labels lived in a side column.
// Counters stay on the label row, right-aligned.

struct CaptionBlock: View {
    @Environment(AppState.self) private var state

    @State private var headline: String = ""
    @State private var caption: String = ""
    @FocusState private var focus: Field?

    private enum Field { case headline, caption }

    private let headlineWarnAt: Int = 36
    private let headlineOverAt: Int = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            VStack(alignment: .leading, spacing: 4) {
                labelRow("Headline",
                         count: headline.count,
                         warnAt: headlineWarnAt,
                         overAt: headlineOverAt)
                headlineInput
            }

            VStack(alignment: .leading, spacing: 4) {
                labelRow("Caption",
                         count: caption.count,
                         warnAt: nil,
                         overAt: nil)
                captionInput
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.bgPanel)
        .overlay(
            Rectangle()
                .fill(Theme.line1)
                .frame(height: 1),
            alignment: .top
        )
        .onAppear { seedFromRecord() }
        .onChange(of: state.selectedRecord?.id ?? "") { _, _ in seedFromRecord() }
    }

    // MARK: - Inputs

    private var headlineInput: some View {
        TextField("", text: $headline)
            .textFieldStyle(.plain)
            .focused($focus, equals: .headline)
            .font(.system(size: 11 * 1.15))
            .foregroundStyle(Theme.fg)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .background(Theme.bgInput)
            .overlay(focusFrame(active: focus == .headline))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private var captionInput: some View {
        TextEditor(text: $caption)
            .focused($focus, equals: .caption)
            .font(.system(size: 11 * 1.15))
            .foregroundStyle(Theme.fgMute)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
            .background(Theme.bgInput)
            .overlay(focusFrame(active: focus == .caption))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func focusFrame(active: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .strokeBorder(active ? Theme.accentEdge : Theme.line1,
                          lineWidth: active ? 1 : 0.5)
    }

    // MARK: - Seeding from store

    private func seedFromRecord() {
        let r = state.selectedRecord
        headline = r?.headline ?? ""
        caption = r?.caption ?? ""
    }

    // MARK: - Label + counter row

    private func labelRow(_ text: String, count: Int, warnAt: Int?, overAt: Int?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(text)
                .font(.system(size: 10 * 1.15, weight: .semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(Theme.fgDim)
            Spacer(minLength: 6)
            counterText(count, warnAt: warnAt, overAt: overAt)
        }
    }

    // String.count returns grapheme cluster count -- what a user perceives
    // as one visible glyph. A single emoji or accented letter counts once.
    private func counterText(_ count: Int, warnAt: Int?, overAt: Int?) -> some View {
        let color: Color = {
            if let overAt, count > overAt { return Theme.no }
            if let warnAt, count >= warnAt { return Theme.warn }
            return Theme.fgFaint
        }()
        return Text(String(count))
            .font(.system(size: 10 * 1.15, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(color)
    }
}
