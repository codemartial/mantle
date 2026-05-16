import SwiftUI
import AppKit

// Custom 44pt title strip that fills the window's title-bar area (with the
// native traffic-light dots showing through on the left). Mirrors the JSX
// Titlebar in app.jsx: divider, folder picker button, sort button, grid /
// list segment, spacer, filter search field.
//
// JSX scope notes:
//   - folder picker is interactive (opens NSOpenPanel via FolderPicker)
//   - sort + search are visual-only in the JSX (no onClick / onChange)
//   - grid / list segment toggles BrowserPane between layouts
//
// The bar is 44pt to match .titlebar { height: 44px } in styles.css.

struct Titlebar: View {
    @Environment(AppState.self) private var state
    @Binding var browserMode: BrowserMode

    private let trafficLightSlot: CGFloat = 78

    var body: some View {
        HStack(spacing: 14) {
            divider
            folderButton
            sortButton
            modeSegment

            Spacer(minLength: 8)

            searchField
        }
        .padding(.leading, trafficLightSlot)
        .padding(.trailing, 12)
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .background(Theme.bgToolbar)
        .overlay(
            Rectangle()
                .fill(Theme.line1)
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    // MARK: - Divider

    private var divider: some View {
        Rectangle()
            .fill(Theme.line1)
            .frame(width: 1, height: 18)
    }

    // MARK: - Folder picker button

    private var folderButton: some View {
        Button {
            FolderPicker.present { url in
                state.openFolder(url)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 11 * 1.15, weight: .regular))
                Text(folderTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\u{25BE}")
                    .font(.system(size: 9 * 1.15))
                    .foregroundStyle(Theme.fgFaint)
            }
            .font(.system(size: 12 * 1.15))
            .foregroundStyle(Theme.fg)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Theme.bgElev)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Theme.line2, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help(folderHelp)
    }

    private var folderTitle: String {
        if let name = state.folderURL?.lastPathComponent, !name.isEmpty {
            return name
        }
        return "Choose folder..."
    }

    private var folderHelp: String {
        state.folderURL?.path ?? "Open folder... (Cmd+O)"
    }

    // MARK: - Sort (visual only)

    private var sortButton: some View {
        Image(systemName: "arrow.up.arrow.down")
            .font(.system(size: 11 * 1.15))
            .foregroundStyle(Theme.fg)
            .frame(width: 26, height: 24)
            .background(Theme.bgElev)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Theme.line2, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .help("Sort")
    }

    // MARK: - Grid / list segment

    private var modeSegment: some View {
        HStack(spacing: 1) {
            modeButton(.grid, icon: "square.grid.2x2")
            modeButton(.list, icon: "list.bullet")
        }
        .padding(1.5)
        .frame(height: 24)
        .background(Theme.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Theme.line2, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func modeButton(_ mode: BrowserMode, icon: String) -> some View {
        Button {
            browserMode = mode
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11 * 1.15, weight: .regular))
                .foregroundStyle(browserMode == mode ? Theme.fg : Theme.fgMute)
                .frame(width: 26, height: 21)
                .background(browserMode == mode ? Theme.bgElevHi : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 3.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Search (visual only)

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11 * 1.15))
                .foregroundStyle(Theme.fgMute)
            Text("Filter keywords, caption...")
                .foregroundStyle(Theme.fgFaint)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12 * 1.15))
        .padding(.horizontal, 8)
        .frame(width: 180, height: 24)
        .background(Theme.bgInput)
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Theme.line1, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

// View-mode for the browser pane. Persisted only in-memory at the moment;
// when the design lands, this can promote to AppStorage or AppState.
enum BrowserMode: String, Hashable {
    case grid
    case list
}

