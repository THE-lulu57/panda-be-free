import Foundation
import Networking
import PandaLogger
import PandaModels
import SwiftUI

private let logCategory = "PrintFiles"

@MainActor
@Observable
public final class PrintFilesViewModel {
    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    public private(set) var files: [PrintFile] = []
    public private(set) var loadState: LoadState = .idle

    private let host: String
    private let accessCode: String

    public init(host: String, accessCode: String) {
        self.host = host
        self.accessCode = accessCode
    }

    /// Lists .gcode.3mf files on the SD card. No thumbnail loading for now —
    /// intentionally removed while we settle on a faster way to get plate
    /// previews than downloading the whole file over FTPS (see chat).
    public func loadFiles() async {
        loadState = .loading
        let service = FTPSService(host: host, accessCode: accessCode)
        do {
            try await service.connect()
            let entries = try await service.list()
            await service.disconnect()
            files = entries
                .filter { !$0.isDirectory && $0.name.lowercased().hasSuffix(".gcode.3mf") }
                .map { PrintFile(path: $0.name, sizeBytes: $0.sizeBytes, modifiedDate: nil) }
                .sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
            loadState = .loaded
            appLog(.info, category: logCategory, "Listed \(files.count) print files")
        } catch {
            appLog(.error, category: logCategory, "Failed to list SD card: \(error.localizedDescription)")
            loadState = .failed(error.localizedDescription)
        }
    }
}
