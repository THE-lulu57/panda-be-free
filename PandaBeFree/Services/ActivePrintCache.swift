import Foundation
import Networking
import PandaLogger
import PandaModels
import SwiftUI

private let logCategory = "ActivePrintCache"

/// Holds thumbnail/time/weight for the print the app itself just started,
/// so the dashboard can show them while printing without re-fetching.
///
/// Populated in the background right after the print command is sent (see
/// PrintFilesListView's onPrintStarted) — the person never waits for this;
/// it just appears once the download+parse finishes. Cleared automatically
/// when the printer leaves the RUNNING state (see DashboardViewModel).
///
/// Known gap: this only works for prints started from this app, since
/// that's the only moment we know the exact SD-card file path. A print
/// started from the printer's own touchscreen won't populate this cache —
/// matching the touchscreen-started case would need guessing a file from
/// `subtask_name`, which isn't reliable enough to build on yet.
@MainActor
@Observable
public final class ActivePrintCache {
    public private(set) var thumbnail: Data?
    public private(set) var estimatedSeconds: Int?
    public private(set) var weightGrams: Double?
    public private(set) var isLoading = false

    public var hasData: Bool { thumbnail != nil || estimatedSeconds != nil || weightGrams != nil }

    @ObservationIgnored private var loadTask: Task<Void, Never>?

    public init() {}

    public func startCaching(file: PrintFile, host: String, accessCode: String) {
        clear()
        isLoading = true
        loadTask = Task { [weak self] in
            guard let self else { return }
            let service = FTPSService(host: host, accessCode: accessCode)
            do {
                try await service.connect()
                let data = try await service.download(path: file.path)
                await service.disconnect()

                let thumbnailData = ThreeMFMetadataExtractor.extractThumbnail(from: data)
                var timeWeight = PlateTimeWeightInfo.unknown
                if let sliceInfoData = ThreeMFMetadataExtractor.extractSliceInfo(from: data) {
                    timeWeight = PlateTimeWeightInfo.parse(sliceInfoXML: sliceInfoData)
                }

                guard !Task.isCancelled else { return }
                self.thumbnail = thumbnailData
                self.estimatedSeconds = timeWeight.predictionSeconds
                self.weightGrams = timeWeight.weightGrams
                self.isLoading = false
                appLog(.info, category: logCategory, "Cached info for \(file.displayName)")
            } catch {
                appLog(.error, category: logCategory, "Failed to cache \(file.path): \(error.localizedDescription)")
                self.isLoading = false
            }
        }
    }

    /// Called when the printer leaves the RUNNING state (finished, failed,
    /// stopped, or a different print started from elsewhere).
    public func clear() {
        loadTask?.cancel()
        loadTask = nil
        thumbnail = nil
        estimatedSeconds = nil
        weightGrams = nil
        isLoading = false
    }
}
