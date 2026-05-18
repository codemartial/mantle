import SwiftUI

// 24px tall bar with subtle middle-dot separators.

struct StatusBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 0) {

            segment {
                Text(itemCountText)
                    .font(.system(size: 11 * 1.15))
                    .foregroundStyle(Theme.fgDim)
                    .monospacedDigit()
            }
            separator()
            segment {
                Text(selectionSummary)
                    .font(.system(size: 11 * 1.15, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Theme.fgDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            separator()
            segment {
                savedFlash
            }

            Spacer(minLength: 0)

            segment {
                Text(sidecarTag)
                    .font(.system(size: 11 * 1.15))
                    .foregroundStyle(Theme.fgFaint)
            }
            separator()
            segment {
                Text(colorProfileTag)
                    .font(.system(size: 11 * 1.15))
                    .foregroundStyle(Theme.fgFaint)
            }
            separator()
            segment {
                Text("v0.1")
                    .font(.system(size: 11 * 1.15, design: .monospaced))
                    .foregroundStyle(Theme.fgFaint)
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Segments

    @ViewBuilder
    private func segment<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 6)
    }

    private func separator() -> some View {
        Circle()
            .fill(Theme.fgFaint.opacity(0.6))
            .frame(width: 3, height: 3)
            .padding(.horizontal, 4)
    }

    // MARK: - Save status

    private var savedFlash: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(statusBackground)
                    .frame(width: 13, height: 13)
                Image(systemName: statusIcon)
                    .font(.system(size: 7 * 1.15, weight: .bold))
                    .foregroundStyle(statusForeground)
            }
            Text(state.status.displayText)
                .font(.system(size: 11 * 1.15))
                .foregroundStyle(statusText)
        }
    }

    private var statusBackground: Color {
        switch state.status {
        case .idle, .saved:   return Theme.ok.opacity(0.18)
        case .unsaved:        return Theme.warn.opacity(0.18)
        case .saving:         return Theme.warn.opacity(0.20)
        case .failed:         return Theme.no.opacity(0.22)
        }
    }

    private var statusForeground: Color {
        switch state.status {
        case .idle, .saved:       return Theme.ok
        case .unsaved, .saving:   return Theme.warn
        case .failed:             return Theme.no
        }
    }

    private var statusText: Color {
        switch state.status {
        case .saved:  return Theme.ok
        default:      return Theme.fgDim
        }
    }

    private var statusIcon: String {
        switch state.status {
        case .idle, .saved: return "checkmark"
        case .unsaved:      return "pencil"
        case .saving:       return "arrow.triangle.2.circlepath"
        case .failed:       return "exclamationmark"
        }
    }

    // MARK: - Text

    private var itemCountText: String {
        guard state.folderURL != nil else { return "0 items" }
        return "\(state.library.count) items"
    }

    private var selectionSummary: String {
        guard let entry = state.selectedEntry else { return "no selection" }
        if let record = state.selectedRecord, record.size > 0 {
            return "\(entry.displayURL.lastPathComponent)  -  \(ByteSize.format(record.size))"
        }
        return entry.displayURL.lastPathComponent
    }

    private var sidecarTag: String {
        guard let entry = state.selectedEntry else { return ".xmp sidecar" }
        return entry.sidecarURL == nil ? ".xmp sidecar (new)" : ".xmp sidecar"
    }

    private var colorProfileTag: String {
        if let record = state.selectedRecord, !record.colorProfile.isEmpty {
            return record.colorProfile
        }
        return "P3  -  Display"
    }
}
