import PandaModels
import SwiftUI

/// The options a person can toggle before starting a print — deliberately
/// small. No per-file color preview here: that would require downloading
/// the whole file first (some are 20+ MB, meaning a multi-minute wait on
/// this printer's known-slow LAN transfer — see chat), just to show
/// something the printer already decides on its own when you start from its
/// touchscreen.
///
/// A manual AMS color-forcing picker used to live here (reusing AMSTrayView)
/// but was removed — it didn't fit visually in this sheet. Colors always
/// follow whatever the slicer set; see the warning text below.
public struct PrintOptions {
    public var bedLeveling: Bool
    public var flowCalibration: Bool
    public var timelapse: Bool
}

public struct PrintConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let file: PrintFile
    let onConfirm: (PrintOptions) -> Void

    @State private var bedLeveling = true
    @State private var flowCalibration = true
    @State private var timelapse = false

    public init(file: PrintFile, onConfirm: @escaping (PrintOptions) -> Void) {
        self.file = file
        self.onConfirm = onConfirm
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Bed Leveling", isOn: $bedLeveling)
                    Toggle("Flow Dynamics Calibration", isOn: $flowCalibration)
                    Toggle("Timelapse", isOn: $timelapse)
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
                            timelapse: timelapse
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
