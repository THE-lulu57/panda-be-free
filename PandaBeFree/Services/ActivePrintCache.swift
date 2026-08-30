import Foundation
import Networking
import PandaLogger
import PandaModels
import SwiftUI

private let logCategory = "ActivePrintCache"

/// Holds thumbnail/time/weight for the print the app itself just started,
/// so the dashboard can show them while printing without re-fetching.
///
/// Registered right after the print command is sent (see PrintFilesListView's
/// onPrintStarted), but the actual FTPS download is deferred until
/// DashboardViewModel observes gcode_state actually reach RUNNING — not
/// started immediately.
///
/// Why the delay: starting our own FTPS download of the same file at the
/// exact moment the print command is sent collided with the printer's own
/// internal read of that file to begin printing. Bambu's onboard FTP server
/// is documented (bambuddy's own notes) as single-socket, prioritizing the
/// active print — a competing download at that exact instant could plausibly
/// make the firmware's own file read fail, which would show up as a generic
/// "couldn't parse the file" error with no connection to anything actually
/// wrong in the print command itself. Waiting for RUNNING means the printer
/// has already finished opening the file on its own before we touch it.
///
/// Cleared automatically when the printer leaves the RUNNING state (see
/// DashboardViewModel).
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

    @ObservationIgnored private var pending: (file: PrintFile, host: String, accessCode: String)?
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    public var hasData: Bool { thumbnail != nil || estimatedSeconds != nil || weightGrams != nil }

    public init() {}

    /// Call right after sending the print command. Does not touch the
    /// network yet — just remembers what to fetch once printing actually
    /// starts (see `printingDidStart`).
    public func registerPendingPrint(file: PrintFile, host: String, accessCode: String) {
        clear()
        pending = (file, host, accessCode)
    }

    /// Call when gcode_state is observed transitioning into RUNNING. Starts
    /// the deferred FTPS download for whatever print was last registered.
    public func printingDidStart() {
        guard let pending else { return }
        self.pending = nil
        isLoading = true
        loadTask = Task { [weak self] in
            guard let self else { return }
            let service = FTPSService(host: pending.host, accessCode: pending.accessCode)
            do {
                try await service.connect()
                let data = try await service.download(path: pending.file.path)
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
                appLog(.info, category: logCategory, "Cached info for \(pending.file.displayName)")
            } catch {
                appLog(.error, category: logCategory, "Failed to cache \(pending.file.path): \(error.localizedDescription)")
                self.isLoading = false
            }
        }
    }

    /// Called when the printer leaves the RUNNING state (finished, failed,
    /// stopped, or a different print started from elsewhere) — or when a new
    /// print is registered before the previous one ever reached RUNNING.
    public func clear() {
        pending = nil
        loadTask?.cancel()
        loadTask = nil
        thumbnail = nil
        estimatedSeconds = nil
        weightGrams = nil
        isLoading = false
    }
}
