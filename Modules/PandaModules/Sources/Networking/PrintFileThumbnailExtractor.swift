import Foundation
import PandaLogger
import ZIPFoundation

private let logCategory = "ThumbnailExtractor"

/// Pulls the plate thumbnail PNG out of a downloaded .gcode.3mf archive
/// (a .gcode.3mf is a plain ZIP file). Confirmed against a real Bambu Lab A1
/// export: the file lives at "Metadata/plate_1.png", generated alongside
/// plate_no_light_1.png / top_1.png / pick_1.png — plate_1.png is the best
/// one to show since it's centered and fully lit.
public enum PrintFileThumbnailExtractor {
    private static let candidatePaths = [
        "Metadata/plate_1.png",
        "Metadata/plate_no_light_1.png",
    ]

    /// Returns PNG data for the plate thumbnail, or nil if the archive
    /// isn't a recognizable sliced Bambu project.
    public static func extractThumbnail(from archiveData: Data) -> Data? {
        guard let archive = try? Archive(data: archiveData, accessMode: .read) else {
            appLog(.error, category: logCategory, "Could not open .gcode.3mf as a ZIP archive")
            return nil
        }

        for path in candidatePaths {
            guard let entry = archive[path] else { continue }
            var extracted = Data()
            do {
                _ = try archive.extract(entry) { chunk in extracted.append(chunk) }
                if !extracted.isEmpty {
                    return extracted
                }
            } catch {
                appLog(.error, category: logCategory, "Failed extracting \(path): \(error.localizedDescription)")
            }
        }
        return nil
    }
}
