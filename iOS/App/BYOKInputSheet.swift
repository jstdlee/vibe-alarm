import SwiftUI
import VibeAlarmCore

/// Clean English sheet for pasting HR/holiday notices or `.ics` URLs and extracting
/// dates on-device (offline rules) or via a Keychain-backed BYOK LLM.
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
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    inputCard
                    actionsCard

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 2)
                    }

                    if let result = extractionResult {
                        resultsCard(result)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .background(Color.vibeCanvas)
            .navigationTitle("Parse Holiday Notice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.vibeAccent)
                }
            }
        }
        .tint(.vibeAccent)
        .preferredColorScheme(.light)
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTICE OR LEAVE EMAIL")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            TextEditor(text: $inputText)
                .frame(minHeight: 100)
                .font(.subheadline)
            Text("Paste a holiday notice, leave email, or a link to an .ics subscription.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .vibeCard()
    }

    private var actionsCard: some View {
        HStack(spacing: 10) {
            Button {
                runOfflineParse()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                    Text("Parse On-Device")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color(uiColor: .systemGray6))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                Task { await runBYOKLLMParse() }
            } label: {
                HStack(spacing: 6) {
                    if isExtracting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text("Parse with BYOK AI")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.vibeAccent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isExtracting)
        }
    }

    private func resultsCard(_ result: BYOKExtractionResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RESULTS")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(Array(result.entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Divider()
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                                .font(.subheadline)
                            Text(entry.date)
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(entry.kind.displayTitle)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(entry.kind == .makeupWorkday ? Color.vibeWork : Color.vibeAccent)
                    }
                    .padding(.vertical, 6)
                }

                ForEach(result.discoveredCalendarURLs, id: \.self) { url in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Calendar Subscription Link")
                            .font(.subheadline)
                        Text(url)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 6)
                }
            }

            Button {
                viewModel.mergeExtractedEntries(result.entries, discoveredURLs: result.discoveredCalendarURLs)
                dismiss()
            } label: {
                Text("Add \(result.entries.count) to Calendar")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color.vibeAccent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(result.entries.isEmpty && result.discoveredCalendarURLs.isEmpty)
        }
        .padding(14)
        .vibeCard()
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
