import SwiftUI

// The browser-grid filter checklist, shown in a popover from the toolbar.
// Each attribute row carries a status: ignore (o), present (tick), absent
// (cross), or -- for text attributes -- a search box. Active criteria
// combine with "all" (the any/all toggle is intentionally not exposed yet;
// LibraryFilter.combine defaults to .all).

struct FilterPanel: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            VStack(alignment: .leading, spacing: 10) {
                ForEach(FilterAttribute.allCases) { attr in
                    row(attr)
                }
            }

            Divider().overlay(Theme.line1)

            Text("Show files that match all of the filter criteria.")
                .font(.system(size: 11 * 1.15))
                .foregroundStyle(Theme.fgMute)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 300)
        .background(Theme.bgPanel)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Filter")
                .font(.system(size: 12 * 1.15, weight: .semibold))
                .foregroundStyle(Theme.fg)
            Spacer()
            if state.filter.isActive {
                Button("Clear") { state.filter = LibraryFilter() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11 * 1.15))
                    .foregroundStyle(Theme.accent)
            }
        }
    }

    // MARK: - Attribute row

    @ViewBuilder
    private func row(_ attr: FilterAttribute) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                statusControl(attr)
                Text(attr.label)
                    .font(.system(size: 12 * 1.15))
                    .foregroundStyle(Theme.fg)
                Spacer(minLength: 0)
            }
            if isMatching(attr) {
                switch attr.matchMode {
                case .text:
                    TextField("Contains text...", text: matchText(attr))
                        .textFieldStyle(.plain)
                        .font(.system(size: 12 * 1.15))
                        .foregroundStyle(Theme.fg)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(Theme.bgInput)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Theme.line1, lineWidth: 0.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .padding(.leading, 4)
                case .chips:
                    ChipEditor(chips: chipsBinding(attr), vocabulary: state.keywordVocabulary)
                        .padding(.leading, 4)
                case .none:
                    EmptyView()
                }
            }
        }
    }

    // MARK: - Status segmented control

    private func statusControl(_ attr: FilterAttribute) -> some View {
        HStack(spacing: 2) {
            ForEach(kinds(for: attr), id: \.self) { kind in
                statusSegment(attr, kind)
            }
        }
        .padding(2)
        .background(Theme.bgInput)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Theme.line1, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func statusSegment(_ attr: FilterAttribute, _ kind: StatusKind) -> some View {
        let selected = currentKind(attr) == kind
        return Button {
            apply(kind, to: attr)
        } label: {
            Image(systemName: kind.symbol)
                .font(.system(size: 11 * 1.15, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Theme.accentFg : Theme.fgMute)
                .frame(width: 24, height: 22)
                .background(selected ? Theme.accent : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help(kind.help)
    }

    // MARK: - Status kinds

    // The selectable statuses, in display order. Binary attributes drop the
    // match option.
    private func kinds(for attr: FilterAttribute) -> [StatusKind] {
        attr.supportsMatch ? StatusKind.allCases : [.ignore, .present, .absent]
    }

    private func currentKind(_ attr: FilterAttribute) -> StatusKind {
        switch state.filter.status(attr) {
        case .ignore:           return .ignore
        case .present:          return .present
        case .absent:           return .absent
        case .matches, .chips:  return .matches
        }
    }

    private func isMatching(_ attr: FilterAttribute) -> Bool {
        currentKind(attr) == .matches
    }

    private func apply(_ kind: StatusKind, to attr: FilterAttribute) {
        switch kind {
        case .ignore:  state.filter.statuses[attr] = .ignore
        case .present: state.filter.statuses[attr] = .present
        case .absent:  state.filter.statuses[attr] = .absent
        case .matches:
            // Preserve any input already entered when re-entering match mode.
            switch attr.matchMode {
            case .text:
                if case .matches = state.filter.status(attr) { return }
                state.filter.statuses[attr] = .matches("")
            case .chips:
                if case .chips = state.filter.status(attr) { return }
                state.filter.statuses[attr] = .chips([])
            case .none:
                break
            }
        }
    }

    private func matchText(_ attr: FilterAttribute) -> Binding<String> {
        Binding(
            get: {
                if case .matches(let q) = state.filter.status(attr) { return q }
                return ""
            },
            set: { state.filter.statuses[attr] = .matches($0) }
        )
    }

    private func chipsBinding(_ attr: FilterAttribute) -> Binding<[FilterChip]> {
        Binding(
            get: {
                if case .chips(let c) = state.filter.status(attr) { return c }
                return []
            },
            set: { state.filter.statuses[attr] = .chips($0) }
        )
    }
}

// Inline keyword-chip editor for a chip-match filter. Mirrors KeywordChips:
// comma / Enter commits, case-insensitive dedupe at add-time, backspace on
// an empty draft removes the last chip, an x removes a chip. Added behavior:
// tapping a chip's body toggles its include / exclude polarity. Include chips
// read like KeywordChips (accent dot); exclude chips are red + strikethrough
// so the negation reads at a glance.
//
// Autocomplete: as the draft is typed it offers case-insensitive PREFIX
// matches from the folder's keyword vocabulary, excluding already-added
// chips. Suggestions carry the vocabulary's existing casing, so typing "be"
// offers "Beach" and accepting it adds "Beach" (not "be"). Up/Down move the
// highlight, Enter / Tab / click accept it, comma still commits the literal
// draft.
private struct ChipEditor: View {
    @Binding var chips: [FilterChip]
    let vocabulary: [String]

    @State private var draft: String = ""
    @State private var highlight: Int = 0
    @FocusState private var inputFocused: Bool

    // Case-insensitive prefix matches from the vocabulary, minus what's
    // already chipped. Capped so the list stays compact.
    private var suggestions: [String] {
        let q = draft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        let existing = Set(chips.map { $0.text.lowercased() })
        return vocabulary
            .filter { $0.lowercased().hasPrefix(q) && !existing.contains($0.lowercased()) }
            .prefix(8)
            .map { $0 }
    }

    private var highlightClamped: Int {
        suggestions.isEmpty ? 0 : min(max(highlight, 0), suggestions.count - 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            chipBox
            if !suggestions.isEmpty {
                suggestionList
            }
        }
    }

    private var chipBox: some View {
        FlowLayout(spacing: 4) {
            ForEach(Array(chips.enumerated()), id: \.offset) { index, chip in
                chipView(chip, at: index)
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

    private var suggestionList: some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element) { idx, s in
                Button {
                    addKeyword(s)
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

    @ViewBuilder
    private func chipView(_ chip: FilterChip, at index: Int) -> some View {
        let accent = chip.exclude ? Theme.no : Theme.accent
        HStack(spacing: 3) {
            Image(systemName: chip.exclude ? "minus" : "plus")
                .font(.system(size: 8 * 1.15, weight: .bold))
                .foregroundStyle(accent)
                .padding(.leading, 6)
            Text(chip.text)
                .font(.system(size: 11 * 1.15))
                .foregroundStyle(Theme.fg)
                .strikethrough(chip.exclude, color: Theme.no)
            Button {
                removeChip(at: index)
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
                .strokeBorder(chip.exclude ? Theme.no.opacity(0.5) : Theme.chipBorder, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
        // Tap the body (not the x) to flip include <-> exclude.
        .contentShape(Rectangle())
        .onTapGesture { toggleExclude(at: index) }
        .help(chip.exclude ? "Excluded -- click to require instead" : "Required -- click to exclude instead")
    }

    private var draftInput: some View {
        TextField(chips.isEmpty ? "Type a keyword, press , to add" : "Add...",
                  text: $draft)
            .textFieldStyle(.plain)
            .focused($inputFocused)
            .font(.system(size: 11 * 1.15))
            .foregroundStyle(Theme.fg)
            .frame(minWidth: 80, idealWidth: 120, maxWidth: .infinity, minHeight: 18)
            .padding(.horizontal, 4)
            .onSubmit { acceptOrCommit() }
            .onChange(of: draft) { _, newValue in
                highlight = 0
                if newValue.contains(",") { commit(newValue) }
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
                addKeyword(suggestions[highlightClamped])
                return .handled
            }
            .onKeyPress(.delete) {
                if draft.isEmpty, !chips.isEmpty {
                    removeChip(at: chips.count - 1)
                    return .handled
                }
                return .ignored
            }
    }

    // MARK: - Mutations

    // Enter: accept the highlighted suggestion if the list is open, else
    // commit whatever's typed as a literal keyword.
    private func acceptOrCommit() {
        if !suggestions.isEmpty {
            addKeyword(suggestions[highlightClamped])
        } else {
            commit(draft)
        }
    }

    // Add a single keyword with exactly the given casing (used by the
    // suggestion list, which carries the vocabulary's canonical form).
    private func addKeyword(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if !chips.contains(where: { $0.text.lowercased() == t.lowercased() }) {
            chips.append(FilterChip(text: t))
        }
        draft = ""
        highlight = 0
    }

    private func commit(_ raw: String) {
        let parts = raw
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { draft = ""; return }
        var existingLower = Set(chips.map { $0.text.lowercased() })
        for part in parts {
            let lower = part.lowercased()
            if existingLower.contains(lower) { continue }
            chips.append(FilterChip(text: part))
            existingLower.insert(lower)
        }
        draft = ""
        highlight = 0
    }

    private func removeChip(at index: Int) {
        guard index < chips.count else { return }
        chips.remove(at: index)
    }

    private func toggleExclude(at index: Int) {
        guard index < chips.count else { return }
        chips[index].exclude.toggle()
    }
}

// UI-only enum for the segmented control -- AttributeFilter carries an
// associated string for .matches, which is awkward to compare per segment.
private enum StatusKind: CaseIterable, Hashable {
    case ignore, present, absent, matches

    var symbol: String {
        switch self {
        case .ignore:  return "circle"
        case .present: return "checkmark"
        case .absent:  return "xmark"
        case .matches: return "magnifyingglass"
        }
    }

    var help: String {
        switch self {
        case .ignore:  return "Ignore this attribute"
        case .present: return "Has this attribute"
        case .absent:  return "Missing this attribute"
        case .matches: return "Matches text"
        }
    }
}
