import SwiftUI

// Batch-mode counterpart to CaptionBlock. Bindings flow to state.batchDraft
// rather than the per-image EditStore -- nothing is broadcast to individual
// images until exitBatch() runs synthesizeBatch().
//
// Blank fields mean "do not modify this field on any image" (multi-edit
// blank-no-modify rule). Caption has two modes: Replace overwrites the
// whole caption on each image, Append concatenates to whatever caption
// each image already has.

struct BatchCaptionBlock: View {
    @Environment(AppState.self) private var state

    @FocusState private var focus: Field?

    private enum Field { case headline, caption }

    var body: some View {
        @Bindable var state = state

        VStack(alignment: .leading, spacing: 10) {

            VStack(alignment: .leading, spacing: 4) {
                labelRow("Title (batch)", count: state.batchDraft.headline.count)
                headlineInput(text: $state.batchDraft.headline)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Description (batch)")
                        .font(.system(size: 10 * 1.15, weight: .semibold))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.fgDim)

                    Picker("", selection: $state.batchDraft.captionMode) {
                        Text("Replace").tag(BatchDraft.CaptionMode.replace)
                        Text("Append").tag(BatchDraft.CaptionMode.append)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.mini)
                    .fixedSize()

                    Spacer(minLength: 6)

                    Text(String(activeCaptionLength(draft: state.batchDraft)))
                        .font(.system(size: 10 * 1.15, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(Theme.fgFaint)
                }

                if state.batchDraft.captionMode == .replace {
                    captionInput(text: $state.batchDraft.captionReplace,
                                 placeholder: "Leave blank to keep each description")
                } else {
                    appendCaptionStack(append: $state.batchDraft.captionAppend)
                }
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

    // MARK: - Inputs

    private func headlineInput(text: Binding<String>) -> some View {
        TextField("Leave blank to keep each title", text: text)
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

    private func captionInput(text: Binding<String>, placeholder: String) -> some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: text)
                .focused($focus, equals: .caption)
                .font(.system(size: 11 * 1.15))
                .foregroundStyle(Theme.fgMute)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 4)
                .padding(.vertical, 8)

            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.system(size: 11 * 1.15))
                    .foregroundStyle(Theme.fgFaint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
        .background(Theme.bgInput)
        .overlay(focusFrame(active: focus == .caption))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    // In append mode, show the master's caption above the append-text input
    // so the user can see what they're concatenating to. Master caption is
    // read-only here; to edit it, they need to single-select the master.
    private func appendCaptionStack(append: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(masterCaption.isEmpty ? "(master description is empty)" : masterCaption)
                .font(.system(size: 11 * 1.15))
                .foregroundStyle(Theme.fgFaint)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
                .background(Theme.bgInput.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Theme.line1, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 5))

            captionInput(text: append, placeholder: "Text to append to every description")
        }
    }

    private var masterCaption: String {
        state.masterRecord?.caption ?? ""
    }

    private func activeCaptionLength(draft: BatchDraft) -> Int {
        switch draft.captionMode {
        case .replace: return draft.captionReplace.count
        case .append:  return draft.captionAppend.count
        }
    }

    private func focusFrame(active: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .strokeBorder(active ? Theme.accentEdge : Theme.line1,
                          lineWidth: active ? 1 : 0.5)
    }

    private func labelRow(_ text: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(text)
                .font(.system(size: 10 * 1.15, weight: .semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(Theme.fgDim)
            Spacer(minLength: 6)
            Text(String(count))
                .font(.system(size: 10 * 1.15, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(Theme.fgFaint)
        }
    }
}
