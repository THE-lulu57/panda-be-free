import Foundation

/// A file listed on the printer's SD card via FTPS. Only .gcode.3mf files
/// (already-sliced projects) are relevant for printing — other entries
/// (folders, cache files) are filtered out before this model is built.
public struct PrintFile: Identifiable, Sendable, Equatable {
    /// Full path on the SD card, e.g. "SnoopyV2.gcode.3mf" — also what's
    /// used as the FTPS RETR path and as the `url` in the project_file
    /// print command.
    public let path: String
    public let sizeBytes: Int64
    public let modifiedDate: Date?

    public var id: String { path }

    /// Filename without the SD card path prefix, for display.
    public var displayName: String {
        (path as NSString).lastPathComponent
    }

    public init(path: String, sizeBytes: Int64, modifiedDate: Date?) {
        self.path = path
        self.sizeBytes = sizeBytes
        self.modifiedDate = modifiedDate
    }
}
