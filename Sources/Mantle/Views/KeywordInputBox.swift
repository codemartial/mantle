import SwiftUI

// A bordered keyword input box shared by every keyword editor: the single
// and batch right-pane editors and the filter's chip editor. The host
// supplies its own chip views (they differ -- plain, common/some, or
// include/exclude); this owns the draft TextField, the autocomplete
// suggestion list, and all the keyboard handling.
//
// Autocomplete offers case-insensitive PREFIX matches from `vocabulary`,
// excluding anything in `existing`. Suggestions carry the vocabulary's
// existing casing, so typing "be" offers "Beach" and accepting adds "Beach"
// (not "be"). Up/Down move the highlight; Enter / Tab / click accept it;
// comma commits the literal typed text (split on commas); backspace on an
// empty draft calls `onBackspaceEmpty`.
//
// `onCommit` receives one keyword at a time (canonical casing from a
// suggestion, or the literal token from comma/Enter). The host owns its own
// dedupe and how the keyword is actually added.
struct KeywordInputBox<Chips: View>: View {
    let vocabulary: [String]
    let existing: [String]            // case-insensitive exclude set for suggestions
    let placeholder: String
    let onCommit: (String) -> Void
    var onBackspaceEmpty: () -> Void = {}
    @ViewBuilder var chips: () -> Chips

    @State private var draft: String = ""
    @State private var highlight: Int = 0
    @FocusState private var inputFocused: Bool

    private var suggestions: [String] {
        let q = draft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        let ex = Set(existing.map { $0.lowercased() })
        return vocabulary
            .filter { $0.lowercased().hasPrefix(q) && !ex.contains($0.lowercased()) }
            .prefix(8)
            .map { $0 }
    }

    private var highlightClamped: Int {
        suggestions.isEmpty ? 0 : min(max(highlight, 0), suggestions.count - 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            box
            if !suggestions.isEmpty {
                suggestionList
            }
        }
    }

    private var box: some View {
        FlowLayout(spacing: 4) {
            chips()
            draftField
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

    private var draftField: some View {
        TextField(placeholder, text: $draft)
            .textFieldStyle(.plain)
            .focused($inputFocused)
            .font(.system(size: 11 * 1.15))
            .foregroundStyle(Theme.fg)
            .frame(minWidth: 80, idealWidth: 120, maxWidth: .infinity, minHeight: 18)
            .padding(.horizontal, 4)
            .onSubmit { acceptOrCommit() }
            .onChange(of: draft) { _, newValue in
                highlight = 0
                if newValue.contains(",") { commitLiteral(newValue) }
            }
            .onKeyPress(.downArrow) {
                guard !suggestions.isEmpty else { return .ignored }
                highlight = min(highlightClamped + 1, suggestions.count - 1)
                return .handled
            }
            .onKeyPress(.upArrow) {
                guard !suggestions.isEmpty else { return .ignored }
                highlight = max(highlightClamped - 1, 0)
                return .handled
            }
            .onKeyPress(.tab) {
                guard !suggestions.isEmpty else { return .ignored }
                accept(suggestions[highlightClamped])
                return .handled
            }
            .onKeyPress(.delete) {
                if draft.isEmpty {
                    onBackspaceEmpty()
                    return .handled
                }
                return .ignored
            }
    }

    private var suggestionList: some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element) { idx, s in
                Button {
                    accept(s)
                } label: {
                    HStack {
                        Text(s)
                            .font(.system(size: 11 * 1.15))
                            .foregroundStyle(Theme.fg)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(idx == highlightClamped ? Theme.accentSoft : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
        .background(Theme.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Theme.line1, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    // MARK: - Commit

    // Enter: accept the highlighted suggestion if the list is open, else
    // commit whatever's typed literally.
    private func acceptOrCommit() {
        if !suggestions.isEmpty {
            accept(suggestions[highlightClamped])
        } else {
            commitLiteral(draft)
        }
    }

    private func accept(_ keyword: String) {
        onCommit(keyword)
        draft = ""
        highlight = 0
    }

    private func commitLiteral(_ raw: String) {
        let parts = raw
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for part in parts { onCommit(part) }
        draft = ""
        highlight = 0
    }
}
