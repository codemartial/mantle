import SwiftUI

// Batch-mode keyword editor. Two visually-distinct chip groups:
//   "common" -- keyword is present in every image of the batch
//   "some"   -- present in at least one but not all
// X on a common chip removes the keyword from every image. Click on a some
// chip promotes it to all (adds to every image that lacks it). The draft
// input at the bottom adds a brand-new keyword to every image.
//
// Unlike caption / headline, keyword broadcasts apply immediately so the
// user sees the chip move between groups in real time. The save itself is
// still deferred until batch exit (the writes accumulate in EditStore but
// no save fires until exitBatch -> flushAll).

struct BatchKeywordChips: View {
    @Environment(AppState.self) private var state

    @State private var draft: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        let common = state.commonKeywords
        let some = state.someKeywords

        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Keywords") {
                Text("\(common.count) all \u{00B7} \(some.count) some")
                    .font(.system(size: 10 * 1.15, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Theme.fgFaint)
            }

            FlowLayout(spacing: 4) {
                ForEach(common, id: \.self) { kw in
                    commonChip(kw)
                }
                ForEach(some, id: \.self) { kw in
                    someChip(kw)
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

            HStack(spacing: 6) {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 5, height: 5)
                Text("in all")
                    .font(.system(size: 10 * 1.15))
                    .foregroundStyle(Theme.fgFaint)
                Text("\u{00B7}")
                    .foregroundStyle(Theme.fgFaint)
                Circle()
                    .strokeBorder(Theme.fgFaint, lineWidth: 0.5)
                    .frame(width: 5, height: 5)
                Text("in some (click to promote)")
                    .font(.system(size: 10 * 1.15))
                    .foregroundStyle(Theme.fgFaint)
                Spacer()
            }
        }
    }

    // MARK: - Chips

    @ViewBuilder
    private func commonChip(_ text: String) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 5, height: 5)
                .padding(.leading, 6)
            Text(text)
                .font(.system(size: 11 * 1.15))
                .foregroundStyle(Theme.fg)
            Button {
                state.removeKeywordFromAll(text)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8 * 1.15, weight: .medium))
                    .foregroundStyle(Theme.fgDim)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove from all")
        }
        .frame(height: 18)
        .background(Theme.chipBg)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Theme.chipBorder, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private func someChip(_ text: String) -> some View {
        Button {
            state.promoteKeywordToAll(text)
        } label: {
            HStack(spacing: 3) {
                Circle()
                    .strokeBorder(Theme.fgDim, lineWidth: 0.5)
                    .frame(width: 5, height: 5)
                    .padding(.leading, 6)
                Text(text)
                    .font(.system(size: 11 * 1.15))
                    .foregroundStyle(Theme.fgMute)
                    .padding(.trailing, 6)
            }
            .frame(height: 18)
            .background(Theme.chipBgSome)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Theme.chipBorder.opacity(0.6), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help("Promote to all images")
    }

    // MARK: - Draft input

    private var draftInput: some View {
        TextField(state.commonKeywords.isEmpty && state.someKeywords.isEmpty
                  ? "Type a keyword, press , to add to all"
                  : "Add to all...",
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
    }

    // MARK: - Mutations

    private func commit(_ raw: String) {
        let parts = raw
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for part in parts {
            state.addKeywordToAll(part)
        }
        draft = ""
    }
}
