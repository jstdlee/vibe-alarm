import SwiftUI
import VibeAlarmCore

/// Paste an HR notice, leave email, or `.ics` link and extract calendar entries
/// either on-device (offline rules) or via the Keychain-backed BYOK LLM.
public struct BYOKInputSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var inputText: String = "HR Notice: I will take annual leave from November 11 to 12, 2026.\nI will work a makeup shift on Saturday, November 21, 2026."
    @State private var isExtracting: Bool = false
    @State private var errorMessage: String?
    @State private var extractionResult: BYOKExtractionResult?

    private let service = BYOKHolidayService()

    public init(viewModel: AppViewModel, preloadPreview: Bool = false) {
        self.viewModel = viewModel
        if preloadPreview {
            let sample = "HR Notice: I will take annual leave from November 11 to 12, 2026.\nI will work a makeup shift on Saturday, November 21, 2026."
            _extractionResult = State(initialValue: BYOKHolidayService().parseLocally(text: sample))
        }
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $inputText)
                        .frame(minHeight: 100)
                        .font(.subheadline)
                } header: {
                    Text("Notice or Leave Email")
                } footer: {
                    Text("Paste a holiday notice, leave email, or a link to an .ics subscription.")
                }

                Section {
                    Button {
                        runOfflineParse()
                    } label: {
                        Label("Parse On-Device", systemImage: "bolt.fill")
                    }

                    Button {
                        Task { await runBYOKLLMParse() }
                    } label: {
                        if isExtracting {
                            HStack {
                                ProgressView()
                                Text("Parsing with BYOK AI…")
                            }
                        } else {
                            Label("Parse with BYOK AI", systemImage: "sparkles")
                        }
                    }
                    .disabled(isExtracting)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let result = extractionResult {
                    resultsSection(result)
                }
            }
            .navigationTitle("Parse Holiday Notice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(.vibeAccent)
    }

    @ViewBuilder
    private func resultsSection(_ result: BYOKExtractionResult) -> some View {
        Section {
            ForEach(result.entries) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                        Text(entry.date)
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(entry.kind.displayTitle)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(result.discoveredCalendarURLs, id: \.self) { url in
                VStack(alignment: .leading, spacing: 2) {
                    Text("Calendar Subscription Link")
                    Text(url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Button {
                viewModel.mergeExtractedEntries(result.entries, discoveredURLs: result.discoveredCalendarURLs)
                dismiss()
            } label: {
                Text("Add \(result.entries.count) to Calendar")
            }
            .disabled(result.entries.isEmpty && result.discoveredCalendarURLs.isEmpty)
        } header: {
            Text("Results")
        }
    }

    private func runOfflineParse() {
        errorMessage = nil
        extractionResult = service.parseLocally(text: inputText)
    }

    private func runBYOKLLMParse() async {
        errorMessage = nil
        let apiKey = KeychainHelper.loadAPIKey()
        if apiKey.isEmpty {
            extractionResult = service.parseLocally(text: inputText)
            errorMessage = "No API key configured. Parsed with on-device rules instead."
            return
        }

        isExtracting = true
        defer { isExtracting = false }

        do {
            let res = try await service.extractHolidaysViaLLM(
                userText: inputText,
                config: viewModel.snapshot.byokConfig,
                apiKey: apiKey
            )
            extractionResult = res
        } catch {
            errorMessage = error.localizedDescription
            extractionResult = service.parseLocally(text: inputText)
        }
    }
}
