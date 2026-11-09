import SwiftUI
import UIKit
import VibeAlarmCore

/// CI/preview-only screen: the small and medium home screen widgets, drawn at their real sizes
/// using the exact shared widget views the extension renders.
public struct WidgetGalleryView: View {
    @ObservedObject var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    galleryItem(caption: "Medium, today and tomorrow", width: 329, height: 155) {
                        MediumWidgetContentView(
                            today: viewModel.todayAlarm,
                            tomorrow: viewModel.tomorrowAlarm
                        )
                    }

                    galleryItem(caption: "Small, tomorrow only", width: 155, height: 155) {
                        SmallWidgetContentView(tomorrow: viewModel.tomorrowAlarm)
                    }

                    Text("Touch and hold a widget to reach Skip and Restore without opening the app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Widgets")
        }
    }

    private func galleryItem<Content: View>(
        caption: String,
        width: CGFloat,
        height: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(caption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            content()
                .padding(16)
                .frame(width: width, height: height, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}
