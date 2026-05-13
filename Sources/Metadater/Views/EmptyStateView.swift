import SwiftUI

struct EmptyStateView: View {
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            // Iconograph -- a simple folder glyph in the accent colour.
            Image(systemName: "folder")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Theme.fgDim)

            VStack(spacing: 6) {
                Text("Open a folder of photos")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.fg)
                Text("Metadater reads EXIF, IPTC and XMP from each image\nand writes your edits to a .xmp sidecar alongside the\noriginal -- RAW files are never modified.")
                    .multilineTextAlignment(.center)
                    .font(Typo.body)
                    .foregroundStyle(Theme.fgDim)
                    .lineSpacing(2)
            }

            HStack(spacing: 8) {
                Button(action: onOpen) {
                    Text("Choose Folder...")
                        .font(Typo.bodyMid)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .keyboardShortcut("o", modifiers: .command)
            }

            Text("or drag a folder onto the window")
                .font(Typo.small)
                .foregroundStyle(Theme.fgFaint)
                .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bgWindow)
    }
}
