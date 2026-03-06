import SwiftUI
import UniformTypeIdentifiers

/// Left panel: drag-and-drop zone for the input image, with a file picker fallback.
struct ImageDropZone: View {
    @Environment(AppState.self) private var state

    @State private var isTargeted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(isTargeted ? Color.accentColor.opacity(0.15) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 2, dash: [8])
                        )
                        .foregroundColor(
                            isTargeted ? .accentColor : .secondary.opacity(0.4)
                        )
                )

            if let image = state.inputImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(16)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Drop an image here")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("or")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Browse...") {
                        pickFile()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
        .padding(8)
    }

    // MARK: - Helpers

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            let ext = url.pathExtension.lowercased()
            guard ["jpg", "jpeg", "png", "heic", "tiff", "bmp"].contains(ext) else { return }
            DispatchQueue.main.async {
                state.setImage(url: url)
            }
        }
        return true
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        state.setImage(url: url)
    }
}
