import Foundation
import Networking
import PandaLogger
import PandaModels
import SwiftUI
import UIKit

private let logCategory = "ActivePrintCache"

/// Holds thumbnail/time/weight/colors for the print the app itself just
/// started, so the dashboard can show them while printing without
/// re-fetching.
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
/// (Confirmed fixed in practice.)
///
/// Cleared automatically when the printer leaves the RUNNING state (see
/// DashboardViewModel).
///
/// ⚠️ Background behavior: this download runs on Network.framework sockets,
/// not URLSession — so it CANNOT use iOS's real background-transfer session
/// (that mechanism only works for URLSession HTTP tasks). What this class
/// does instead is request a `beginBackgroundTask` grace period, which buys
/// roughly 30 seconds up to a few minutes (iOS decides, not guaranteed) once
/// the app is backgrounded. That covers briefly switching apps; it does NOT
/// mean the transfer reliably finishes if the phone is locked and left for a
/// while — iOS can and will suspend the process once the grace period ends,
/// same as any other iOS app without a registered background mode. There is
/// no "Background Activity" entry for this because no proper iOS background
/// mode (background fetch, background URLSession, VoIP, etc.) is registered
/// — the beginBackgroundTask API doesn't produce one.
///
/// ⚠️ Force-quit recovery: all of the above state is plain in-memory —
/// force-quitting the app (not just backgrounding it) kills the process and
/// wipes it, same as any other in-memory app state. What survives is a
/// single breadcrumb in SharedSettings (`lastStartedPrintFilePath`, just a
/// filename — not sensitive) written when the print starts and cleared when
/// it ends. On relaunch, `recoverIfNeeded` uses that breadcrumb to redo the
/// FTPS download and repopulate the card if the same print is still RUNNING
/// — this is a full re-fetch, not a restored cache, so it costs the same
/// network transfer again. It does not verify the breadcrumb still matches
/// the actual running job (e.g. if a different print started from the
/// touchscreen in between) — an edge case rare enough, and low-stakes enough
/// (a cosmetic dashboard card, not anything print-safety-related), not to be
/// worth the added complexity of cross-checking against subtask_name yet.
///
/// Known gap: this only works for prints started from this app, since
/// that's the only moment we know the exact SD-card file path. A print
/// started from the printer's own touchscreen won't populate this cache —
/// matching the touchscreen-started case would need guessing a file from
/// `subtask_name`, which isn't reliable enough to build on yet.
@MainActor
@Observable
public final class ActivePrintCache {
    public private(set) var fileName: String?
    public private(set) var thumbnail: Data?
    public private(set) var estimatedSeconds: Int?
    public private(set) var weightGrams: Double?
    public private(set) var colorHexes: [String]?
    public private(set) var isLoading = false

    @ObservationIgnored private var pending: (file: PrintFile, host: String, accessCode: String)?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    public var hasData: Bool { thumbnail != nil || estimatedSeconds != nil || weightGrams != nil }

    public init() {}

    /// Call right after sending the print command. Does not touch the
    /// network yet — just remembers what to fetch once printing actually
    /// starts (see `printingDidStart`), and persists the file path so a
    /// force-quit + relaunch can recover it (see `recoverIfNeeded`).
    public func registerPendingPrint(file: PrintFile, host: String, accessCode: String) {
        clear()
        pending = (file, host, accessCode)
        SharedSettings.lastStartedPrintFilePath = file.path
    }

    /// Call on every printer state update while nothing is cached yet and
    /// no print is otherwise pending. Cheap to call repeatedly — it only
    /// does real work the first time it finds something to recover after a
    /// force-quit + relaunch while a print this app started is still
    /// RUNNING. See the type's doc comment for what this does and doesn't
    /// guarantee.
    public func recoverIfNeeded(gcodeState: String, host: String, accessCode: String) {
        guard !hasData, !isLoading, pending == nil,
              gcodeState == "RUNNING",
              let path = SharedSettings.lastStartedPrintFilePath
        else { return }
        appLog(.info, category: logCategory, "Recovering active-print cache after relaunch for \(path)")
        pending = (PrintFile(path: path, sizeBytes: 0, modifiedDate: nil), host, accessCode)
        printingDidStart()
    }

    /// Call when gcode_state is observed transitioning into RUNNING. Starts
    /// the deferred FTPS download for whatever print was last registered.
    public func printingDidStart() {
        guard let pending else { return }
        self.pending = nil
        isLoading = true
        fileName = pending.file.displayName

        // Ask iOS for extra run time in case the app gets backgrounded
        // mid-download — see the type's doc comment for what this can and
        // can't guarantee.
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "ActivePrintCache.download") { [weak self] in
            // iOS calls this on a background queue, not MainActor — must
            // hop explicitly before touching actor-isolated state.
            Task { @MainActor [weak self] in
                self?.loadTask?.cancel()
                self?.endBackgroundTask()
            }
        }

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
                // Colors come from the same downloaded bytes — no extra
                // network cost over what the thumbnail/time already needed.
                var colors: [String]?
                if let projectSettingsData = ThreeMFMetadataExtractor.extractProjectSettings(from: data) {
                    colors = SlicedProjectColors.parse(jsonData: projectSettingsData)?.colorHexes
                }

                guard !Task.isCancelled else { return }
                self.thumbnail = thumbnailData
                self.estimatedSeconds = timeWeight.predictionSeconds
                self.weightGrams = timeWeight.weightGrams
                self.colorHexes = colors
                self.isLoading = false
                appLog(.info, category: logCategory, "Cached info for \(pending.file.displayName)")
            } catch {
                appLog(.error, category: logCategory, "Failed to cache \(pending.file.path): \(error.localizedDescription)")
                self.isLoading = false
            }
            self.endBackgroundTask()
        }
    }

    /// Called when the printer leaves the RUNNING state (finished, failed,
    /// stopped, or a different print started from elsewhere) — or when a new
    /// print is registered before the previous one ever reached RUNNING.
    public func clear() {
        pending = nil
        loadTask?.cancel()
        loadTask = nil
        endBackgroundTask()
        fileName = nil
        thumbnail = nil
        estimatedSeconds = nil
        weightGrams = nil
        colorHexes = nil
        isLoading = false
        SharedSettings.lastStartedPrintFilePath = nil
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
}
