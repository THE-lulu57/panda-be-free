import PandaModels
import SwiftUI

/// The options a person can toggle before starting a print — deliberately
/// small. No per-file color *preview* here: that would require downloading
/// the whole file first (some are 20+ MB, meaning a multi-minute wait on
/// this printer's known-slow LAN transfer — see chat), just to show
/// something the printer already decides on its own when you start from its
/// touchscreen.
///
/// The one exception is `forcedTray`: forcing a single AMS slot doesn't need
/// the file at all — it only uses the AMS state the app already has live via
/// MQTT. Meant for mono-color files (a full multi-color remap still isn't
/// supported — see the warning text below).
public struct PrintOptions {
    public var bedLeveling: Bool
    public var flowCalibration: Bool
    public var timelapse: Bool
    /// (amsUnitId, traySlot) if the person forced a specific spool, else nil
    /// (printer decides, same as starting from its own screen).
    public var forcedTray: (amsUnitId: Int, traySlot: Int)?
}

public struct PrintConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let file: PrintFile
    let amsUnits: [(unitId: Int, trays: [AMSTray])]
    let onConfirm: (PrintOptions) -> Void

    @State private var bedLeveling = true
    @State private var flowCalibration = true
    @State private var timelapse = false
    @State private var forcedTray: ForcedTraySelection = .auto

    public init(
        file: PrintFile,
        amsUnits: [(unitId: Int, trays: [AMSTray])] = [],
        onConfirm: @escaping (PrintOptions) -> Void
    ) {
        self.file = file
        self.amsUnits = amsUnits
        self.onConfirm = onConfirm
    }

    private var loadedTrays: [(unitId: Int, tray: AMSTray)] {
        amsUnits.flatMap { unit in unit.trays.filter { !$0.isEmpty }.map { (unit.unitId, $0) } }
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Bed Leveling", isOn: $bedLeveling)
                    Toggle("Flow Dynamics Calibration", isOn: $flowCalibration)
                    Toggle("Timelapse", isOn: $timelapse)
                }

                if !loadedTrays.isEmpty {
                    Section {
                        Picker("Force color", selection: $forcedTray) {
                            Text("Auto (printer decides)").tag(ForcedTraySelection.auto)
                            ForEach(loadedTrays, id: \.tray.id) { entry in
                                HStack {
                                    if let color = entry.tray.color {
                                        Circle().fill(color).frame(width: 14, height: 14)
                                    }
                                    Text("AMS \(entry.unitId + 1) · Slot \(entry.tray.id + 1) — \(entry.tray.materialType ?? "")")
                                }
                                .tag(ForcedTraySelection.forced(unitId: entry.unitId, traySlot: entry.tray.id))
                            }
                        }
                    } footer: {
                        Text("Only forces the first color of the print. Best for single-color files — for multi-color files, colors follow what's set in the slicer.")
                    }
                }

                Section {
                    Label(
                        "This will print with the filament colors set in the slicer. To change colors, start the print from the printer's screen instead.",
                        systemImage: "info.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Send to Printer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Print") {
                        onConfirm(PrintOptions(
                            bedLeveling: bedLeveling,
                            flowCalibration: flowCalibration,
                            timelapse: timelapse,
                            forcedTray: forcedTray.tray
                        ))
                    }
                    .fontWeight(.semibold)
                }
            }
            .safeAreaInset(edge: .top) {
                Text(file.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
        }
        .presentationDetents([.medium])
    }
}

private enum ForcedTraySelection: Hashable {
    case auto
    case forced(unitId: Int, traySlot: Int)

    var tray: (amsUnitId: Int, traySlot: Int)? {
        if case let .forced(unitId, traySlot) = self { (unitId, traySlot) } else { nil }
    }
}
