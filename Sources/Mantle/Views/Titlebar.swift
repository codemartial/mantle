import SwiftUI
import AppKit

// Custom 44pt title strip that fills the window's title-bar area (with the
// native traffic-light dots showing through on the left). Mirrors the JSX
// Titlebar in app.jsx: divider, folder picker button, sort button, spacer,
// filter search field.
//
// Diverges from the JSX in one place: the grid / list view-mode segment
// is omitted. The app only browses thumbnails -- list mode was dropped to
// simplify the toolbar and the BrowserPane.
//
// Scope notes:
//   - folder picker is interactive (opens NSOpenPanel via FolderPicker)
//   - sort + search are visual-only (no onClick / onChange)
//
// The bar is 44pt to match .titlebar { height: 44px } in styles.css.

struct Titlebar: View {
    @Environment(AppState.self) private var state

    // Width of the leading slot reserved for the system traffic-light
    // buttons. AppDelegate shifts the buttons +8pt right, so they occupy
    // x = 15..69 (close at x=15, miniaturize at x=35, zoom at x=55, each
    // 14pt wide). An 83pt slot puts a 14pt gap between zoom's trailing
    // edge and the divider -- matching the HStack's 14pt spacing between
    // the divider and the folder button after it.
    private let trafficLightSlot: CGFloat = 83

    var body: some View {
        HStack(spacing: 14) {
            divider
            folderButton
            sortButton

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
