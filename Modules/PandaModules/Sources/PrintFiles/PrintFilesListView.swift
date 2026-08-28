import PandaModels
import SwiftUI

public struct PrintFilesListView: View {
    @State private var viewModel: PrintFilesViewModel
    @State private var fileToConfirm: PrintFile?
    private let host: String
    private let accessCode: String
    private let amsUnits: [(unitId: Int, trays: [AMSTray])]
    private let sendCommand: (PrinterCommand) -> Void
    private let onPrintStarted: (PrintFile) -> Void

    public init(
        host: String,
        accessCode: String,
        amsUnits: [(unitId: Int, trays: [AMSTray])] = [],
        sendCommand: @escaping (PrinterCommand) -> Void = { _ in },
        onPrintStarted: @escaping (PrintFile) -> Void = { _ in }
    ) {
        _viewModel = State(initialValue: PrintFilesViewModel(host: host, accessCode: accessCode))
        self.host = host
        self.accessCode = accessCode
        self.amsUnits = amsUnits
        self.sendCommand = sendCommand
        self.onPrintStarted = onPrintStarted
    }

    public var body: some View {
        NavigationStack {
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
                        Button {
                            fileToConfirm = file
                        } label: {
                            PrintFileRow(file: file)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Print")
            .task { await viewModel.loadFiles() }
            .sheet(item: $fileToConfirm) { file in
                PrintConfirmationSheet(file: file, amsUnits: amsUnits) { options in
                    let amsMapping = options.forcedTray.map { [$0.amsUnitId * 4 + $0.traySlot] }
                    sendCommand(.projectFile(
                        filePath: file.path,
                        plateGcode: "Metadata/plate_1.gcode",
                        subtaskName: file.displayName,
                        useAMS: true,
                        amsMapping: amsMapping, // nil = let the printer auto-match, same as its touchscreen
                        flowCalibration: options.flowCalibration,
                        bedLeveling: options.bedLeveling,
                        timelapse: options.timelapse
                    ))
                    onPrintStarted(file)
                    fileToConfirm = nil
                }
            }
        }
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
                    .foregroundStyle(.primary)
                Text(sizeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: file.sizeBytes, countStyle: .file)
    }
}
