// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import SwiftUI

struct EmptyStateView: View {
    let onOpen: () -> Void

    var body: some View {
        ZStack {
            StripedBackground()

            VStack(spacing: 14) {
                dashedIcon

                VStack(spacing: 6) {
                    Text("Point Mantle at a folder of images")
                        .font(.system(size: 14 * 1.15, weight: .semibold))
                        .foregroundStyle(Theme.fg)

                    Text("Drag any folder onto the window, or use Cmd+O to choose one. Mantle reads EXIF, IPTC and XMP from each image and writes your edits to a .xmp sidecar alongside the original -- RAW files are never modified.")
                        .font(.system(size: 12 * 1.15))
                        .foregroundStyle(Theme.fgDim)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2.5)
                }

                HStack(spacing: 8) {
                    Button(action: onOpen) {
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                                .font(.system(size: 11 * 1.15, weight: .medium))
                            Text("Choose folder...")
                                .font(.system(size: 12 * 1.15, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .keyboardShortcut("o", modifiers: .command)

                    Button(action: {}) {
                        HStack(spacing: 4) {
                            Text("Open recent")
                                .font(.system(size: 12 * 1.15))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9 * 1.15, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .disabled(true)
                }
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dashedIcon: some View {
        RoundedRectangle(cornerRadius: 14)
            .strokeBorder(
                Theme.line2,
                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
            )
            .frame(width: 64, height: 64)
            .overlay(
                ZStack {
                    Image(systemName: "folder")
                        .font(.system(size: 26 * 1.15, weight: .light))
                        .foregroundStyle(Theme.fgDim)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13 * 1.15))
                        .foregroundStyle(Theme.accent)
                        .background(Theme.bgWindow.clipShape(Circle()))
                        .offset(x: 11, y: 9)
                }
            )
    }
}
