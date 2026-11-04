import SwiftUI
import VibeAlarmCore
import WidgetKit

/// CI/preview-only screen: the small and medium home screen widgets, drawn at their real sizes
/// on the paper, using the exact shared widget views the extension renders.
public struct WidgetGalleryView: View {
    @ObservedObject var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 34) {
                    Text("VIBE ALARM")
                        .vibeCaption()
                        .padding(.top, 14)
                    Text("Widgets")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(VibePalette.ink)
                        .padding(.top, -22)

                    galleryItem(caption: "Medium · today and tomorrow", width: 329, height: 155) {
                        MediumWidgetContentView(
                            today: viewModel.todayAlarm,
                            tomorrow: viewModel.tomorrowAlarm
                        )
                    }

                    galleryItem(caption: "Small · tomorrow only", width: 155, height: 155) {
                        SmallWidgetContentView(tomorrow: viewModel.tomorrowAlarm)
                    }

                    Text("Long press a widget to reach Skip and Restore without opening the app.")
                        .font(.system(size: 11.5))
                        .lineSpacing(3)
                        .foregroundStyle(VibePalette.inkFaint)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(VibePalette.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(VibePalette.amber)
    }

    private func galleryItem<Content: View>(
        caption: String,
        width: CGFloat,
        height: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(caption.uppercased())
                .vibeCaption(VibePalette.inkSoft)
            content()
                .padding(16)
                .frame(width: width, height: height)
                .background(VibePalette.paperDeep)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(VibePalette.hairline.opacity(0.5), lineWidth: 0.6)
                )
                .shadow(color: VibePalette.shadow.opacity(0.14), radius: 12, x: 0, y: 6)
        }
    }
}
