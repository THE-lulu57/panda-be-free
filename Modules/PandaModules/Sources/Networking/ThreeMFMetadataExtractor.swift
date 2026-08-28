import Foundation
import PandaLogger
import ZIPFoundation

private let logCategory = "3MFMetadata"

/// Pulls specific small entries out of a downloaded .gcode.3mf archive (a
/// .gcode.3mf is a plain ZIP file) — never the embedded gcode itself, which
/// is what makes up the bulk of the file's size. Used to populate the
/// active-print cache shown on the dashboard while a print is running:
/// thumbnail, estimated time, filament weight.
public enum ThreeMFMetadataExtractor {
    private static let thumbnailPaths = [
        "Metadata/plate_1.png",
        "Metadata/plate_no_light_1.png",
    ]

    public static func extractSliceInfo(from archiveData: Data) -> Data? {
        extract(entryPath: "Metadata/slice_info.config", from: archiveData)
    }

    /// Returns PNG data for the plate thumbnail, or nil if not present.
    public static func extractThumbnail(from archiveData: Data) -> Data? {
        for path in thumbnailPaths {
            if let data = extract(entryPath: path, from: archiveData) {
                return data
            }
        }
        return nil
    }

    private static func extract(entryPath: String, from archiveData: Data) -> Data? {
        guard let archive = try? Archive(data: archiveData, accessMode: .read) else {
            appLog(.error, category: logCategory, "Could not open .gcode.3mf as a ZIP archive")
            return nil
        }
        guard let entry = archive[entryPath] else {
            return nil
        }
        var extracted = Data()
        do {
            _ = try archive.extract(entry) { chunk in extracted.append(chunk) }
            return extracted.isEmpty ? nil : extracted
        } catch {
            appLog(.error, category: logCategory, "Failed extracting \(entryPath): \(error.localizedDescription)")
            return nil
        }
    }
}
