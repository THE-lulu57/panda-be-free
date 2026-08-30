import Foundation

/// Just the colors used by a sliced plate, parsed from
/// `Metadata/project_settings.config` (JSON despite the .config extension).
/// Display-only — no AMS tray matching (that was dropped as too complex for
/// the print-launch flow; see chat). Used to decorate the dashboard's
/// active-print card using bytes already downloaded for the thumbnail, so
/// this adds no extra network cost.
public struct SlicedProjectColors {
    /// Hex colors as written by the slicer, e.g. "#FF0000" (no alpha).
    public let colorHexes: [String]

    public static func parse(jsonData: Data) -> SlicedProjectColors? {
        guard let root = try? JSONDecoder().decode(RawProjectSettings.self, from: jsonData),
              !root.filamentColour.isEmpty else { return nil }
        return SlicedProjectColors(colorHexes: root.filamentColour)
    }

    private struct RawProjectSettings: Decodable {
        let filamentColour: [String]
        enum CodingKeys: String, CodingKey {
            case filamentColour = "filament_colour"
        }
    }
}
