import PandaModels
import Shimmer
import SwiftUI

public struct PrintFilesListView: View {
    @State private var viewModel: PrintFilesViewModel

    public init(host: String, accessCode: String) {
        _viewModel = State(initialValue: PrintFilesViewModel(host: host, accessCode: accessCode))
    }

    public var body: some View {
        Group {
            switch viewModel.loadState {
            case .idle, .loading:
                ProgressView("Reading SD card…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message):
                ContentUnavailableView {
                    Label("Couldn't read SD card", systemImage: "sdcard.fill")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") { Task { await viewModel.loadFiles() } }
                }
            case .loaded where viewModel.files.isEmpty:
                ContentUnavailableView(
                    "No print files found",
                    systemImage: "sdcard.fill",
                    description: Text("No .gcode.3mf files on the SD card.")
                )
            case .loaded:
                List(viewModel.files) { file in
                    PrintFileRow(file: file, thumbnail: viewModel.thumbnails[file.path])
                        .onAppear { viewModel.loadThumbnailIfNeeded(for: file) }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Print")
        .task { await viewModel.loadFiles() }
    }
}

private struct PrintFileRow: View {
    let file: PrintFile
    let thumbnail: Data?

    var body: some View {
        HStack(spacing: 12) {
            thumbnailView
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(file.displayName)
                    .font(.body)
                    .lineLimit(2)
                Text(sizeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail, let uiImage = UIImage(data: thumbnail) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary)
                .shimmering()
        }
    }

    private var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: file.sizeBytes, countStyle: .file)
    }
}
