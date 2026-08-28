import Foundation

/// Estimated print time and filament weight for one plate, parsed from
/// `Metadata/slice_info.config` (XML) inside a .gcode.3mf archive.
///
/// Not guaranteed to be present: at least one real-world sample seen during
/// development had a slice_info.config with no `<plate>` block at all (just
/// the header). Callers should treat `nil` fields as "unknown", not as a
/// parsing failure — there's nothing else on the SD card that would give us
/// this data cheaply, so unknown is the honest answer, not an error state.
public struct PlateTimeWeightInfo: Sendable, Equatable {
    public let predictionSeconds: Int?
    public let weightGrams: Double?

    public static let unknown = PlateTimeWeightInfo(predictionSeconds: nil, weightGrams: nil)

    /// - Parameter plateIndex: 1-based plate index (almost always 1 for a
    ///   single-plate export). If no `<plate>` matches, falls back to the
    ///   first `<plate>` block found, since most SD-card files are
    ///   single-plate anyway.
    public static func parse(sliceInfoXML data: Data, plateIndex: Int = 1) -> PlateTimeWeightInfo {
        guard let xml = String(data: data, encoding: .utf8) else { return .unknown }

        let blocks = xml.components(separatedBy: "<plate>").dropFirst().compactMap { chunk -> String? in
            guard let end = chunk.range(of: "</plate>") else { return nil }
            return String(chunk[chunk.startIndex..<end.lowerBound])
        }

        let match = blocks.first { intValue(forKey: "index", in: $0) == plateIndex } ?? blocks.first
        guard let block = match else { return .unknown }

        return PlateTimeWeightInfo(
            predictionSeconds: intValue(forKey: "prediction", in: block),
            weightGrams: doubleValue(forKey: "weight", in: block)
        )
    }

    private static func intValue(forKey key: String, in block: String) -> Int? {
        rawMetadataValue(forKey: key, in: block).flatMap(Int.init)
    }

    private static func doubleValue(forKey key: String, in block: String) -> Double? {
        rawMetadataValue(forKey: key, in: block).flatMap(Double.init)
    }

    private static func rawMetadataValue(forKey key: String, in block: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<metadata\s+key="\#(key)"\s+value="([^"]*)"\s*/>"#
        ) else { return nil }
        let range = NSRange(block.startIndex..., in: block)
        guard let match = regex.firstMatch(in: block, range: range),
              let valueRange = Range(match.range(at: 1), in: block) else { return nil }
        return String(block[valueRange])
    }
}
