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
    public static func extractSliceInfo(from archiveData: Data) -> Data? {
        extract(entryPath: "Metadata/slice_info.config", from: archiveData)
    }

    /// Returns PNG data for the plate thumbnail, or nil if not present.
    ///
    /// The thumbnail's plate number in the filename doesn't always match the
    /// gcode's — confirmed on a real file where the print gcode was
    /// `plate_1.gcode` but the thumbnail was `plate_4.png`, not
    /// `plate_1.png`. So this searches the archive's actual entries instead
    /// of guessing a fixed name, preferring a plain "plate_N.png" over the
    /// "_small" thumbnail variant when both exist.
    public static func extractThumbnail(from archiveData: Data) -> Data? {
        guard let archive = try? Archive(data: archiveData, accessMode: .read) else {
            appLog(.error, category: logCategory, "Could not open .gcode.3mf as a ZIP archive")
            return nil
        }

        let candidates = archive.compactMap { entry -> String? in
            let path = entry.path
            guard path.hasPrefix("Metadata/plate_"), path.hasSuffix(".png") else { return nil }
            return path
        }
        // Prefer the full-size thumbnail over "_small" or "no_light" variants.
        let chosen = candidates.first { !$0.contains("_small") && !$0.contains("no_light") } ?? candidates.first
        guard let path = chosen else {
            appLog(.info, category: logCategory, "No plate thumbnail found in this archive")
            return nil
        }
        return extract(entryPath: path, from: archive)
    }

    private static func extract(entryPath: String, from archiveData: Data) -> Data? {
        guard let archive = try? Archive(data: archiveData, accessMode: .read) else {
            appLog(.error, category: logCategory, "Could not open .gcode.3mf as a ZIP archive")
            return nil
        }
        return extract(entryPath: entryPath, from: archive)
    }

    private static func extract(entryPath: String, from archive: Archive) -> Data? {
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
