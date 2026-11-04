import SwiftUI
import UIKit
import VibeAlarmCore

/// A searchable list of built-in public-holiday calendars. The user types a country name or
/// ISO code and taps a row to subscribe. Rows that are already subscribed show a checkmark
/// instead of an "Add" affordance. Presented as a large sheet from the Sources tab, and also
/// rendered directly as the root in the "search" UI-preview mode.
public struct HolidayCatalogSearchSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var query: String

    public init(viewModel: AppViewModel, initialQuery: String = "") {
        self.viewModel = viewModel
        _query = State(initialValue: initialQuery)
    }

    /// Catalog matches for the current query (full list sorted by name when empty).
    private var results: [HolidayCatalogItem] {
        HolidayCatalog.search(query)
    }

    public var body: some View {
        NavigationStack {
            List {
                ForEach(results) { item in
                    catalogRow(item)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Add Holidays")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Country or code")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(.vibeAccent)
    }

    // MARK: - Row

    private func catalogRow(_ item: HolidayCatalogItem) -> some View {
        let subscribed = viewModel.isSubscribed(item)
        return Button {
            guard !subscribed else { return }
            add(item)
        } label: {
            HStack(spacing: 12) {
                isoBadge(item.isoCode)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.countryName)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(secondaryLine(for: item))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if subscribed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.vibeAccent)
                        .accessibilityLabel("Added")
                } else {
                    Text("Add")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.vibeAccent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.vibeAccent.opacity(0.12)))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(subscribed)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.countryName), \(item.isoCode)")
        .accessibilityValue(subscribed ? "Added" : "Not added")
    }

    private func isoBadge(_ code: String) -> some View {
        Text(code)
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 36, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(.secondarySystemFill))
            )
    }

    private func secondaryLine(for item: HolidayCatalogItem) -> String {
        switch item.kind {
        case .chinaStatutory:
            return "Statutory holidays and makeup workdays"
        case .google:
            return "Google public holidays"
        }
    }

    private func add(_ item: HolidayCatalogItem) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        viewModel.subscribe(to: item)
    }
}
