import SwiftUI
import UIKit
import VibeAlarmCore

/// A searchable list of the built-in public holiday calendars.
///
/// Type a country name or a two-letter code; the list narrows as you type. A row that is already
/// subscribed shows its state in ink rather than a button, so the sheet reads as a catalogue
/// rather than a set of offers. Presented as a large sheet from Sources, and also rendered
/// directly as the root in the "search" UI-preview mode.
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
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    searchWell
                        .padding(.top, 6)

                    HStack {
                        Text(query.isEmpty ? "All countries" : "Results")
                            .vibeCaption(VibePalette.inkSoft)
                        Spacer()
                        Text("\(results.count)")
                            .font(.footnote.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(VibePalette.inkFaint)
                    }
                    .padding(.top, 26)
                    .padding(.bottom, 10)

                    Hairline()

                    ForEach(results) { item in
                        catalogRow(item)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .background(VibePalette.paper.ignoresSafeArea())
            .navigationTitle("Add Holidays")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(VibePalette.amber)
                }
            }
        }
        .tint(VibePalette.amber)
    }

    // MARK: - Search

    /// A hand-cut search field: recessed well, no capsule, no magnifier glyph.
    private var searchWell: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                TextField("Country or code", text: $query)
                    .font(.body)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(VibePalette.ink)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(VibePalette.inkFaint)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear Search")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .recessedWell(corner: 14)
        }
    }

    // MARK: - Row

    private func catalogRow(_ item: HolidayCatalogItem) -> some View {
        let subscribed = viewModel.isSubscribed(item)
        return VStack(spacing: 0) {
            Button {
                guard !subscribed else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.subscribe(to: item)
            } label: {
                HStack(alignment: .center, spacing: 14) {
                    Text(item.isoCode)
                        .font(.footnote.weight(.semibold).monospaced())
                        .foregroundStyle(VibePalette.inkFaint)
                        .frame(width: 26, alignment: .leading)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.countryName)
                            .font(.body.weight(subscribed ? .light : .regular))
                            .foregroundStyle(subscribed ? VibePalette.inkSoft : VibePalette.ink)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        Text(secondaryLine(for: item))
                            .font(.footnote)
                            .foregroundStyle(VibePalette.inkFaint)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    if subscribed {
                        Text("Added")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(VibePalette.inkFaint)
                    } else {
                        Text("Add")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(VibePalette.amber)
                    }
                }
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(subscribed)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(item.countryName), \(item.isoCode)")
            .accessibilityValue(subscribed ? "Added" : "Not added")

            Hairline()
        }
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
