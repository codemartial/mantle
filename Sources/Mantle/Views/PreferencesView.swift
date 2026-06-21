// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import SwiftUI

struct PreferencesView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        Form {
            Picker("Number keys in batch mode", selection: $state.batchRatingNumberShortcut) {
                ForEach(BatchRatingNumberShortcutPreference.allCases) { choice in
                    Text(choice.label).tag(choice)
                }
            }
            .pickerStyle(.radioGroup)
        }
        .padding(20)
        .frame(width: 360)
    }
}
