import SwiftUI

struct ActivePrintInfoCard: View {
    @Bindable var cache: ActivePrintCache

    var body: some View {
        HStack(spacing: 12) {
            thumbnailView
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                if let seconds = cache.estimatedSeconds {
                    Label(formattedDuration(seconds), systemImage: "clock")
                        .font(.subheadline)
                }
                if let weight = cache.weightGrams {
                    Label(String(format: "%.0f g", weight), systemImage: "scalemass")
                        .font(.subheadline)
                }
                if cache.estimatedSeconds == nil, cache.weightGrams == nil, cache.thumbnail == nil {
                    Text("Loading print details…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
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
            RoundedRectangle(cornerRadius: 10)
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
}
