import SwiftUI
import VibeAlarmCore

/// CI/preview-only screen: renders the small and medium widget views side by
/// side on a plain grouped background, reusing the exact shared widget views.
public struct WidgetGalleryView: View {
    @ObservedObject var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    galleryItem(title: "Small") {
                        SmallWidgetContentView(tomorrow: viewModel.tomorrowAlarm)
                            .padding(16)
                            .frame(width: 155, height: 155)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }

                    galleryItem(title: "Medium") {
                        MediumWidgetContentView(today: viewModel.todayAlarm, tomorrow: viewModel.tomorrowAlarm)
                            .padding(16)
                            .frame(width: 329, height: 155)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Widgets")
        }
        .tint(.vibeAccent)
    }

    private func galleryItem<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }
}
