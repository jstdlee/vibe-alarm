import SwiftUI
import UIKit
import VibeAlarmCore

/// A searchable list of the built-in public holiday calendars.
///
/// Type a country name or a two-letter code; the list narrows as you type. A row that is already
/// subscribed shows its state in the row rather than a second control. Presented as a large sheet
/// from Sources, and also rendered directly as the root in the "search" UI-preview mode.
public struct HolidayCatalogSearchSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var query: String

    public init(viewModel: AppViewModel, initialQuery: String = "") {
        self.viewModel = viewModel
        _query = State(initialValue: initialQuery)
    }

    private var results: [HolidayCatalogItem] {
        HolidayCatalog.search(query)
    }

    public var body: some View {
        NavigationStack {
            List(results) { item in
                catalogRow(item)
            }
            .navigationTitle("Add Holidays")
            .vibeChrome()
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Country or code")
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func catalogRow(_ item: HolidayCatalogItem) -> some View {
        let subscribed = viewModel.isSubscribed(item)
        return Button {
            guard !subscribed else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            viewModel.subscribe(to: item)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Text(item.isoCode)
                    .font(.subheadline.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.countryName)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(secondaryLine(for: item))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Text(subscribed ? "Added" : "Add")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(subscribed ? Color.secondary : Color.primary)
            }
        }
        .buttonStyle(.plain)
        .disabled(subscribed)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.countryName), \(item.isoCode)")
        .accessibilityValue(subscribed ? "Added" : "Not added")
    }

    private func secondaryLine(for item: HolidayCatalogItem) -> String {
        switch item.kind {
        case .chinaStatutory:
            return "Statutory holidays and makeup workdays"
        case .google:
            return "Public holidays"
        }
    }
}
