import PandaModels
import PandaUI
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
    @State private var isColorPickerExpanded = false

    public init(
        file: PrintFile,
        amsUnits: [(unitId: Int, trays: [AMSTray])] = [],
        onConfirm: @escaping (PrintOptions) -> Void
    ) {
        self.file = file
        self.amsUnits = amsUnits
        self.onConfirm = onConfirm
    }

    private var hasAnyLoadedTray: Bool {
        amsUnits.contains { $0.trays.contains { !$0.isEmpty } }
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Bed Leveling", isOn: $bedLeveling)
                    Toggle("Flow Dynamics Calibration", isOn: $flowCalibration)
                    Toggle("Timelapse", isOn: $timelapse)
                }

                if hasAnyLoadedTray {
                    Section {
                        DisclosureGroup(
                            isExpanded: $isColorPickerExpanded,
                            content: { colorForcingContent },
                            label: { colorForcingLabel }
                        )
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
        .presentationDetents([.medium, .large])
    }

    private var colorForcingLabel: some View {
        HStack {
            Text("Force color")
            Spacer()
            if case let .forced(unitId, traySlot) = forcedTray,
               let tray = amsUnits.first(where: { $0.unitId == unitId })?.trays.first(where: { $0.id == traySlot })
            {
                if let color = tray.color {
                    Circle().fill(color).frame(width: 14, height: 14)
                }
                Text(tray.materialType ?? "")
                    .foregroundStyle(.secondary)
            } else {
                Text("Auto").foregroundStyle(.secondary)
            }
        }
    }

    /// Reuses AMSTrayView — the same spool-card component shown on the
    /// dashboard — so this looks and feels like the rest of the app instead
    /// of a generic list picker.
    private var colorForcingContent: some View {
        VStack(spacing: 12) {
            ForEach(amsUnits, id: \.unitId) { unit in
                HStack(spacing: 8) {
                    ForEach(unit.trays) { tray in
                        AMSTrayView(
                            tray: tray,
                            slotLabel: "A\(tray.id + 1)",
                            isActive: forcedTray == .forced(unitId: unit.unitId, traySlot: tray.id),
                            onTap: tray.isEmpty ? nil : {
                                forcedTray = (forcedTray == .forced(unitId: unit.unitId, traySlot: tray.id))
                                    ? .auto
                                    : .forced(unitId: unit.unitId, traySlot: tray.id)
                            }
                        )
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private enum ForcedTraySelection: Hashable {
    case auto
    case forced(unitId: Int, traySlot: Int)

    var tray: (amsUnitId: Int, traySlot: Int)? {
        if case let .forced(unitId, traySlot) = self { (unitId, traySlot) } else { nil }
    }
}
