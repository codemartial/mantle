import SwiftUI

// Headline + caption editors anchored below the preview in the center pane.
// Design pass: read-only display from the EditStore. Editable bindings + a
// dirty set are wired up after the design is approved.

struct CaptionBlock: View {
    @Environment(AppState.self) private var state

    private let labelWidth: CGFloat = 70

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {

            // HEADLINE row
            HStack(alignment: .center, spacing: 10) {
                rowLabel("Headline")
                headlineInput
                rowCounter(headlineCounter)
            }

            // CAPTION row
            HStack(alignment: .top, spacing: 10) {
                rowLabel("Caption")
                    .padding(.top, 6)
                captionInput
                rowCounter(captionCounter)
                    .padding(.top, 6)
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
    }

    // MARK: - Inputs (read-only for now)

    private var headlineInput: some View {
        HStack(spacing: 0) {
            Text(headlineText)
                .font(.system(size: 11 * 1.15))
                .foregroundStyle(headlineForeground)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        .background(Theme.bgInput)
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Theme.line1, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private var captionInput: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(captionText)
                .font(.system(size: 11 * 1.15))
                .foregroundStyle(captionForeground)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
        .background(Theme.bgInput)
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Theme.line1, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    // MARK: - Text + counters

    private var headlineText: String {
        if let r = state.selectedRecord, !r.headline.isEmpty { return r.headline }
        return "(no headline)"
    }

    private var headlineForeground: Color {
        guard let r = state.selectedRecord, !r.headline.isEmpty else { return Theme.fgFaint }
        return Theme.fg
    }

    private var captionText: String {
        if let r = state.selectedRecord, !r.caption.isEmpty { return r.caption }
        return "(no caption)"
    }

    private var captionForeground: Color {
        guard let r = state.selectedRecord, !r.caption.isEmpty else { return Theme.fgFaint }
        return Theme.fgMute
    }

    private var headlineCounter: String {
        // String.count returns grapheme cluster count -- what users perceive
        // as visible glyphs (a single emoji or accented letter counts as one).
        String(state.selectedRecord?.headline.count ?? 0)
    }

    private var captionCounter: String {
        String(state.selectedRecord?.caption.count ?? 0)
    }

    // MARK: - Row helpers

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10 * 1.15, weight: .semibold))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(Theme.fgDim)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(width: labelWidth, alignment: .leading)
    }

    private func rowCounter(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10 * 1.15, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(Theme.fgFaint)
            .frame(minWidth: 26, alignment: .trailing)
    }
}
