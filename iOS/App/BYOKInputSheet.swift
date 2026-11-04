import SwiftUI
import VibeAlarmCore

/// Paste an HR notice, a leave email or a link to an `.ics` feed and turn it into calendar entries,
/// either with the on-device rules or through the user's own key.
///
/// The paste area is a recessed well, the ways to read it are two milled keys, and the results are
/// a plain list of engraved lines. Nothing is boxed.
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
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("PASTE")
                        .vibeCaption()
                        .padding(.top, 8)

                    TextEditor(text: $inputText)
                        .font(.system(size: 14))
                        .foregroundStyle(VibePalette.ink)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 132)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .recessedWell(corner: 14)
                        .overlay(alignment: .topLeading) {
                            if inputText.isEmpty {
                                Text("A holiday notice, a leave email, or a link to an .ics feed.")
                                    .font(.system(size: 14))
                                    .foregroundStyle(VibePalette.inkFaint)
                                    .padding(.horizontal, 17)
                                    .padding(.vertical, 18)
                                    .allowsHitTesting(false)
                            }
                        }
                        .padding(.top, 8)

                    HStack(spacing: 12) {
                        actionKey(title: "READ ON DEVICE", enabled: !isExtracting) {
                            errorMessage = nil
                            extractionResult = service.parseLocally(text: inputText)
                        }
                        actionKey(
                            title: isExtracting ? "READING" : "READ WITH KEY",
                            enabled: !isExtracting
                        ) {
                            Task { await runBYOKLLMParse() }
                        }
                    }
                    .padding(.top, 16)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 11.5))
                            .lineSpacing(2)
                            .foregroundStyle(VibePalette.inkFaint)
                            .padding(.top, 12)
                    }

                    if let result = extractionResult {
                        results(result)
                            .padding(.top, 28)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .background(VibePalette.paper.ignoresSafeArea())
            .navigationTitle("Parse Notice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(VibePalette.inkSoft)
                }
            }
        }
        .tint(VibePalette.amber)
    }

    private func actionKey(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(VibePalette.ink.opacity(enabled ? 1 : 0.4))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .machinedPlate(corner: 15, raised: enabled)
        }
        .buttonStyle(KeyPressStyle())
        .disabled(!enabled)
    }

    // MARK: - Results

    private func results(_ result: BYOKExtractionResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("FOUND")
                    .vibeCaption(VibePalette.inkSoft)
                Spacer()
                Text("\(result.entries.count)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(VibePalette.inkFaint)
            }
            .padding(.bottom, 10)

            Hairline()

            ForEach(result.entries) { entry in
                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.title)
                                .font(.system(size: 15))
                                .foregroundStyle(VibePalette.ink)
                            Text(entry.date)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(VibePalette.inkFaint)
                        }
                        Spacer(minLength: 8)
                        Text(entry.kind.displayTitle.uppercased())
                            .vibeCaption(VibePalette.inkFaint)
                    }
                    .padding(.vertical, 13)
                    Hairline()
                }
            }

            ForEach(result.discoveredCalendarURLs, id: \.self) { url in
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Calendar feed found")
                            .font(.system(size: 15))
                            .foregroundStyle(VibePalette.ink)
                        Text(url)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(VibePalette.inkFaint)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 13)
                    Hairline()
                }
            }

            Button {
                viewModel.mergeExtractedEntries(result.entries, discoveredURLs: result.discoveredCalendarURLs)
                dismiss()
            } label: {
                Text("ADD TO CALENDAR")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(VibePalette.amber)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .machinedPlate(corner: 15)
            }
            .buttonStyle(KeyPressStyle())
            .disabled(result.entries.isEmpty && result.discoveredCalendarURLs.isEmpty)
            .padding(.top, 22)
        }
    }

    // MARK: - Parsing

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
