import SwiftUI

struct ActivePrintInfoCard: View {
    @Bindable var cache: ActivePrintCache

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            thumbnailView
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 6) {
                if let fileName = cache.fileName {
                    Text(fileName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                }

                if let seconds = cache.estimatedSeconds {
                    Label(formattedDuration(seconds), systemImage: "clock")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let weight = cache.weightGrams {
                    Label(String(format: "%.0f g", weight), systemImage: "scalemass")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let colors = cache.colorHexes, !colors.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(colors.indices, id: \.self) { index in
                            Circle()
                                .fill(colorFromHex(colors[index]))
                                .frame(width: 14, height: 14)
                                .overlay(Circle().strokeBorder(.secondary.opacity(0.3), lineWidth: 0.5))
                        }
                    }
                    .padding(.top, 2)
                }

                if cache.estimatedSeconds == nil, cache.weightGrams == nil, cache.thumbnail == nil {
                    Text("Loading print details…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail = cache.thumbnail, let uiImage = UIImage(data: thumbnail) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary)
                .overlay {
                    if cache.isLoading {
                        ProgressView()
                    }
                }
        }
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    /// Local, minimal hex parser (colorHexes come as plain "#RRGGBB" strings
    /// from the slicer, no existing hex→Color helper for that direction in
    /// the codebase — only the reverse exists, in AMSState.swift).
    private func colorFromHex(_ hex: String) -> Color {
        var cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6 || cleaned.count == 8 else { return .gray }
        if cleaned.count == 6 { cleaned += "FF" }
        guard let value = UInt32(cleaned, radix: 16) else { return .gray }
        let r = Double((value >> 24) & 0xFF) / 255
        let g = Double((value >> 16) & 0xFF) / 255
        let b = Double((value >> 8) & 0xFF) / 255
        let a = Double(value & 0xFF) / 255
        return Color(red: r, green: g, blue: b, opacity: a)
    }
}
