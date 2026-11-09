import SwiftUI
import VibeAlarmCore

/// Paste an HR notice, a leave email or a link to an `.ics` feed and turn it into calendar entries,
/// either with the on-device rules or through the user's own key.
public struct BYOKInputSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var inputText: String = ""
    @State private var isExtracting: Bool = false
    @State private var errorMessage: String?
    @State private var extractionResult: BYOKExtractionResult?

    private let service = BYOKHolidayService()
    private let sampleNotice = "Annual leave from November 11 to 12, 2026.\nMakeup shift on Saturday, November 21, 2026."

    public init(viewModel: AppViewModel, preloadPreview: Bool = false) {
        self.viewModel = viewModel
        if preloadPreview {
            _inputText = State(initialValue: sampleNotice)
            _extractionResult = State(initialValue: BYOKHolidayService().parseLocally(text: sampleNotice))
        }
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $inputText)
                        .frame(minHeight: 140)
                        .accessibilityLabel("Notice")
                } header: {
                    Text("Paste")
                } footer: {
                    Text("A holiday notice, a leave email, or a link to an .ics feed.")
                }

                Section {
                    Button("Read on Device") {
                        errorMessage = nil
                        extractionResult = service.parseLocally(text: inputText)
                    }
                    .disabled(isExtracting)

                    Button(isExtracting ? "Reading" : "Read with Key") {
                        Task { await runBYOKLLMParse() }
                    }
                    .disabled(isExtracting)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.secondary)
                    }
                }

                if let result = extractionResult {
                    results(result)
                }
            }
            .navigationTitle("Parse Notice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func results(_ result: BYOKExtractionResult) -> some View {
        Section {
            ForEach(result.entries) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                    Text(entry.date)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.secondary)
                    Text(entry.kind.displayTitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(result.discoveredCalendarURLs, id: \.self) { url in
                VStack(alignment: .leading, spacing: 2) {
                    Text("Calendar feed found")
                    Text(url)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        } header: {
            Text("Found \(result.entries.count)")
        }

        Section {
            Button("Add to Calendar") {
                viewModel.mergeExtractedEntries(result.entries, discoveredURLs: result.discoveredCalendarURLs)
                dismiss()
            }
            .disabled(result.entries.isEmpty && result.discoveredCalendarURLs.isEmpty)
        }
    }

    private func runBYOKLLMParse() async {
        errorMessage = nil
        let apiKey = KeychainHelper.loadAPIKey()
        if apiKey.isEmpty {
            extractionResult = service.parseLocally(text: inputText)
            errorMessage = "No key configured. Read with the on-device rules instead."
            return
        }

        isExtracting = true
        defer { isExtracting = false }

        do {
            extractionResult = try await service.extractHolidaysViaLLM(
                userText: inputText,
                config: viewModel.snapshot.byokConfig,
                apiKey: apiKey
            )
        } catch {
            errorMessage = error.localizedDescription
            extractionResult = service.parseLocally(text: inputText)
        }
    }
}
