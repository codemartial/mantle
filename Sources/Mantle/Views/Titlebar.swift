// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

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
//   - the filter button opens FilterPanel (real, drives BrowserPane)
//   - sort toggles state.sortOrder (asc / desc filename), driving the grid
//
// The bar is 44pt to match .titlebar { height: 44px } in styles.css.

struct Titlebar: View {
    @Environment(AppState.self) private var state
    @State private var showFilter = false

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
            rescanButton
            sortButton

            Spacer(minLength: 8)

            if state.headlineSweepRemaining > 0 && headlineFilterActive {
                Text("Reading titles...")
                    .font(.system(size: 11 * 1.15))
                    .foregroundStyle(Theme.fgFaint)
                    .lineLimit(1)
            }
            filterButton
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

    // MARK: - Rescan current folder

    private var rescanButton: some View {
        Button {
            state.rescan()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11 * 1.15))
                .foregroundStyle(state.folderURL == nil ? Theme.fgFaint : Theme.fg)
                .frame(width: 26, height: 24)
                .background(Theme.bgElev)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Theme.line2, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .disabled(state.folderURL == nil)
        .help("Rescan folder")
    }

    // MARK: - Sort (filename asc / desc)

    private var sortButton: some View {
        Button {
            state.sortOrder = state.sortOrder.toggled
        } label: {
            Image(systemName: state.sortOrder.symbolName)
                .font(.system(size: 11 * 1.15))
                .foregroundStyle(Theme.fg)
                .frame(width: 26, height: 24)
                .background(Theme.bgElev)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Theme.line2, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help(state.sortOrder.help)
    }

    // MARK: - Filter

    private var headlineFilterActive: Bool {
        state.filter.status(.headline).constrains
    }

    private var filterButton: some View {
        let active = state.filter.isActive
        let count = state.filter.activeAttributes.count
        return Button {
            // Opening the dialog is a save-point: commit the current edit
            // session before any filter can hide / fragment it.
            if !showFilter { state.flushBeforeFilter() }
            showFilter.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 11 * 1.15))
                Text(active ? "Filter (\(count))" : "Filter")
                    .lineLimit(1)
            }
            .font(.system(size: 12 * 1.15))
            .foregroundStyle(active ? Theme.accentFg : Theme.fg)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(active ? Theme.accent : Theme.bgElev)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(active ? Theme.accentEdge : Theme.line2, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help("Filter the library")
        .popover(isPresented: $showFilter, arrowEdge: .bottom) {
            FilterPanel()
                .environment(state)
        }
    }
}
