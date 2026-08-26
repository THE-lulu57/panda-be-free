import Foundation

/// One filament color slot used by a sliced project, as recorded by the
/// slicer in `Metadata/project_settings.config` (a JSON file, despite the
/// .config extension) inside the .gcode.3mf archive.
///
/// Important: this data is NOT tied to physical AMS trays. The slicer only
/// knows "this project uses N colors of these types/hex values" — it has no
/// idea which AMS slot the user will load them into later. The printer's
/// touchscreen resolves that at print time by matching these fields against
/// whatever is currently loaded in the AMS, and the app needs to do the same
/// (see `AMSMappingSuggester`).
public struct PlateFilament: Identifiable, Sendable, Equatable {
    /// 0-based index — position in the slicer's filament arrays, and the
    /// same index used by `ams_mapping` when starting the print.
    public let index: Int
    /// e.g. "GFL03". Matches `AMSTray.trayInfoIdx` when the exact same
    /// filament SKU is loaded — the most reliable auto-match signal.
    public let filamentId: String
    /// e.g. "PLA", "PETG"
    public let type: String
    /// Hex color as written by the slicer, e.g. "#161616" (no alpha).
    public let colorHex: String
    /// e.g. "Bambu PLA Basic @BBL A1"
    public let settingsName: String

    public var id: Int { index }

    /// Normalized to the app's RRGGBBAA format (used by `AMSTray.colorHex`)
    /// so the two can be compared directly. Assumes full opacity.
    public var normalizedRGBA: String {
        colorHex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased() + "FF"
    }
}

/// Parsed subset of `Metadata/project_settings.config` needed to drive the
/// print-launch screen: how many colors the plate uses, and what they are.
public struct SlicedProjectInfo: Sendable, Equatable {
    public let printerModel: String
    public let filaments: [PlateFilament]

    public var isMultiColor: Bool { filaments.count > 1 }

    /// - Parameter jsonData: raw contents of Metadata/project_settings.config
    /// Throws if the file isn't valid JSON or is missing the arrays this
    /// needs — callers should treat that as "not a recognizable Bambu
    /// project" rather than silently showing zero colors.
    public static func parse(jsonData: Data) throws -> SlicedProjectInfo {
        let root = try JSONDecoder().decode(RawProjectSettings.self, from: jsonData)

        let count = min(
            root.filamentColour.count,
            root.filamentIds.count,
            root.filamentType.count
        )
        guard count > 0 else {
            throw ParseError.noFilamentsFound
        }

        let filaments = (0..<count).map { i in
            PlateFilament(
                index: i,
                filamentId: root.filamentIds[i],
                type: root.filamentType[i],
                colorHex: root.filamentColour[i],
                settingsName: root.filamentSettingsId.indices.contains(i)
                    ? root.filamentSettingsId[i] : root.filamentType[i]
            )
        }

        return SlicedProjectInfo(printerModel: root.printerModel, filaments: filaments)
    }

    public enum ParseError: Error {
        case noFilamentsFound
    }

    /// Mirrors only the JSON keys we need — project_settings.config has
    /// hundreds of slicer settings we don't care about.
    private struct RawProjectSettings: Decodable {
        let filamentColour: [String]
        let filamentIds: [String]
        let filamentType: [String]
        let filamentSettingsId: [String]
        let printerModel: String

        enum CodingKeys: String, CodingKey {
            case filamentColour = "filament_colour"
            case filamentIds = "filament_ids"
            case filamentType = "filament_type"
            case filamentSettingsId = "filament_settings_id"
            case printerModel = "printer_model"
        }
    }
}
