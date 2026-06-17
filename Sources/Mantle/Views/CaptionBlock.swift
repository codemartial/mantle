// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import SwiftUI
import AppKit

// Headline + caption editors anchored below the preview in the center pane.
// Labels sit ABOVE their inputs (not beside them, as the JSX did) so the
// input fields can use the full center-pane width -- the Swift app's left
// and right columns are wider than the JSX prototype's, which left only a
// narrow strip for the inputs when the labels lived in a side column.
// Counters stay on the label row, right-aligned.

struct CaptionBlock: View {
    @Environment(AppState.self) private var state

    @FocusState private var focus: Field?

    private enum Field { case headline, caption }

    private let headlineWarnAt: Int = 36
    private let headlineOverAt: Int = 40

    // Shift+Tab is delivered as the back-tab control character (U+0019),
    // not as .tab with a shift modifier, so the Tab handler below has to
    // match it explicitly to advance focus backward out of the editor.
    private let backTab = Character("\u{19}")

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            VStack(alignment: .leading, spacing: 4) {
                labelRow("Title",
                         count: headlineValue.count,
                         warnAt: headlineWarnAt,
                         overAt: headlineOverAt)
                headlineInput
            }

            VStack(alignment: .leading, spacing: 4) {
                labelRow("Description",
                         count: captionValue.count,
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
    }

    // MARK: - Bindings (read from store, write through AppState)

    private var headlineValue: String { state.selectedRecord?.headline ?? "" }
    private var captionValue: String  { state.selectedRecord?.caption ?? "" }

    private var headlineBinding: Binding<String> {
        Binding(
            get: { headlineValue },
            set: { newValue in
                guard let id = state.selectedID else { return }
                state.updateField(id: id, field: .headline) { $0.headline = newValue }
            }
        )
    }

    private var captionBinding: Binding<String> {
        Binding(
            get: { captionValue },
            set: { newValue in
                guard let id = state.selectedID else { return }
                state.updateField(id: id, field: .caption) { $0.caption = newValue }
            }
        )
    }

    // MARK: - Inputs

    private var headlineInput: some View {
        TextField("", text: headlineBinding)
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
        // TextEditor adds ~5pt lineFragmentPadding internally on the
        // horizontal axis but zero on the vertical, so visually-equal
        // padding requires an asymmetric outer .padding to compensate.
        // 4pt horizontal + ~5pt internal -> ~9pt visible inset.
        // 8pt vertical + ~0pt internal -> ~8pt visible inset.
        TextEditor(text: captionBinding)
            .focused($focus, equals: .caption)
            // TextEditor wraps a multi-line NSTextView, which inserts a tab
            // character on Tab -- unlike a single-line TextField, whose field
            // editor maps Tab to "advance focus". Intercept Tab / back-tab
            // here (onKeyPress fires before the text view's own insertTab:)
            // and drive the window's key-view loop so they move to the next /
            // previous control instead of typing into the editor.
            .onKeyPress(keys: [.tab, KeyEquivalent(backTab)]) { press in
                let goBack = press.modifiers.contains(.shift)
                    || press.key.character == backTab
                if goBack {
                    NSApp.keyWindow?.selectPreviousKeyView(nil)
                } else {
                    NSApp.keyWindow?.selectNextKeyView(nil)
                }
                return .handled
            }
            .font(.system(size: 11 * 1.15))
            .foregroundStyle(Theme.fgMute)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
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
