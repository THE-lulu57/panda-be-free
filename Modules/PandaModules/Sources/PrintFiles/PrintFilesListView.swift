import PandaModels
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
                    PrintFileRow(file: file)
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

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 40)

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

    private var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: file.sizeBytes, countStyle: .file)
    }
}
