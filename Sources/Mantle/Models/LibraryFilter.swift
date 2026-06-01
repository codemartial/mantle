// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import Foundation

// A per-attribute filter for the browser grid. The user picks a status for
// each attribute; the grid shows files matching the combined criteria.
//
// This is the first slice of a checklist that will grow more attributes
// (caption, keywords, GPS, ...). New attributes are added by extending
// FilterAttribute and handling them in AppState.matches(_:_:_:); the value
// types here stay generic.

// How an attribute's "match" status behaves: no match status (binary
// attribute), a free-text substring box, or a list of keyword chips.
enum MatchMode {
    case none
    case text
    case chips
}

// One keyword chip in a chip-match filter. An include chip means the file
// must carry the keyword; an exclude chip means it must not.
struct FilterChip: Equatable, Hashable {
    var text: String
    var exclude: Bool = false   // false = must-have, true = must-not-have
}

// Which file attribute a row filters on.
enum FilterAttribute: String, CaseIterable, Identifiable {
    case xmp        // .xmp sidecar presence -- binary, no match status
    case headline   // title -- free-text match
    case keywords   // subject tags -- chip match (include / exclude)

    var id: String { rawValue }

    var label: String {
        switch self {
        case .xmp:      return "XMP sidecar"
        case .headline: return "Title"
        case .keywords: return "Keywords"
        }
    }

    var matchMode: MatchMode {
        switch self {
        case .xmp:      return .none
        case .headline: return .text
        case .keywords: return .chips
        }
    }

    // Binary attributes (xmp) offer ignore / present / absent only. The
    // others add a "match" status (text box or chip editor).
    var supportsMatch: Bool { matchMode != .none }
}

// The status of one attribute row.
enum AttributeFilter: Equatable {
    case ignore             // o     -- attribute does not constrain the list
    case present            // tick  -- file has the attribute
    case absent             // cross -- file is missing the attribute
    case matches(String)    // search box -- text attributes only
    case chips([FilterChip]) // chip editor -- keyword attributes only

    // A match status with no usable input (empty text / no non-blank chips)
    // is treated as inert, same as ignore, so it doesn't hide everything.
    var constrains: Bool {
        switch self {
        case .ignore:           return false
        case .present, .absent: return true
        case .matches(let q):   return !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .chips(let c):     return c.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }
}

// How active criteria combine. Defaults to .all; no UI toggle in this
// version, but the field exists so an any/all control can be added later
// without reshaping the model.
enum FilterCombine {
    case all
    case any
}

struct LibraryFilter: Equatable {
    var statuses: [FilterAttribute: AttributeFilter] = [:]
    var combine: FilterCombine = .all

    func status(_ attr: FilterAttribute) -> AttributeFilter {
        statuses[attr] ?? .ignore
    }

    // The attributes that currently constrain the list.
    var activeAttributes: [FilterAttribute] {
        FilterAttribute.allCases.filter { status($0).constrains }
    }

    var isActive: Bool {
        !activeAttributes.isEmpty
    }
}
