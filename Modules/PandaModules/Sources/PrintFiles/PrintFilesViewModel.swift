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
    /// Thumbnail PNG data per file path, filled in lazily as rows appear.
    public private(set) var thumbnails: [String: Data] = [:]

    private let host: String
    private let accessCode: String
    private var thumbnailTasks: [String: Task<Void, Never>] = [:]

    public init(host: String, accessCode: String) {
        self.host = host
        self.accessCode = accessCode
    }

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

    /// Downloads a file and extracts its thumbnail the first time a row for
    /// it appears on screen. Safe to call repeatedly — only one download
    /// runs per file, and results are cached in `thumbnails`.
    public func loadThumbnailIfNeeded(for file: PrintFile) {
        guard thumbnails[file.path] == nil, thumbnailTasks[file.path] == nil else { return }

        thumbnailTasks[file.path] = Task { [weak self] in
            guard let self else { return }
            let service = FTPSService(host: host, accessCode: accessCode)
            do {
                try await service.connect()
                let data = try await service.download(path: file.path)
                await service.disconnect()
                if let thumbnail = PrintFileThumbnailExtractor.extractThumbnail(from: data) {
                    await MainActor.run { self.thumbnails[file.path] = thumbnail }
                }
            } catch {
                appLog(.error, category: logCategory, "Thumbnail load failed for \(file.path): \(error.localizedDescription)")
            }
            await MainActor.run { self.thumbnailTasks[file.path] = nil }
        }
    }
}
