import SwiftUI
import VibeAlarmCore

/// Native Apple HIG sheet for parsing holiday notices, HR leave emails, or `.ics` URLs
/// via on-device deterministic rules or Keychain-backed BYOK LLM.
public struct BYOKInputSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var inputText: String = "HR通知：我将在 2026年10月26日到10月28日休年假，10月31日周六调休补班。"
    @State private var isExtracting: Bool = false
    @State private var errorMessage: String?
    @State private var extractionResult: BYOKExtractionResult?

    private let service = BYOKHolidayService()

    public init(viewModel: AppViewModel, preloadPreview: Bool = false) {
        self.viewModel = viewModel
        if preloadPreview {
            let sample = "HR通知：我将在 2026年10月26日到10月28日休年假，10月31日周六调休补班。"
            _extractionResult = State(initialValue: BYOKHolidayService().parseLocally(text: sample))
        }
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    TextEditor(text: $inputText)
                        .frame(minHeight: 100)
                        .font(.body)
                } header: {
                    Text("通知或请假文本")
                        .textCase(nil)
                } footer: {
                    Text("支持粘贴放假通知、请假邮件或包含 .ics 的订阅链接。默认优先在设备本地离线解析。")
                }

                Section {
                    Button {
                        runOfflineParse()
                    } label: {
                        HStack {
                            Text("本地规则解析")
                                .foregroundStyle(.orange)
                            Spacer()
                            Text("离线")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        Task { await runBYOKLLMParse() }
                    } label: {
                        HStack {
                            Text("使用 BYOK 模型提取")
                                .foregroundStyle(.orange)
                            Spacer()
                            if isExtracting {
                                ProgressView()
                            } else {
                                Text(viewModel.snapshot.byokConfig.model)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
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
                    Section {
                        ForEach(result.entries) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title)
                                        .font(.body)
                                    Text(entry.date)
                                        .font(.footnote.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(entry.kind.displayTitle)
                                    .font(.footnote)
                                    .foregroundStyle(entry.kind == .makeupWorkday ? Color.orange : Color.secondary)
                            }
                        }

                        ForEach(result.discoveredCalendarURLs, id: \.self) { url in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("日历订阅链接")
                                    .font(.subheadline)
                                Text(url)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Button {
                            viewModel.mergeExtractedEntries(result.entries, discoveredURLs: result.discoveredCalendarURLs)
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Text("写入假期日历 (\(result.entries.count) 项)")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.orange)
                                Spacer()
                            }
                        }
                        .disabled(result.entries.isEmpty && result.discoveredCalendarURLs.isEmpty)
                    } header: {
                        Text("解析结果")
                            .textCase(nil)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("解析放假通知")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(.orange)
                }
            }
        }
        .tint(.orange)
        .preferredColorScheme(.dark)
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
            errorMessage = "未配置 API Key，已使用本地规则完成解析。"
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
