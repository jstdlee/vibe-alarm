import SwiftUI
import VibeAlarmCore

/// Sheet for pasting HR emails, government holiday announcements, natural language leave notes,
/// or `.ics` links. Supports both direct on-device BYOK LLM extraction (using Keychain API Key)
/// and deterministic offline natural-language parsing.
public struct BYOKInputSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var inputText: String = "HR通知：我将在 2026年10月26日到10月28日休年假，10月31日周六调休补班。"
    @State private var isExtracting: Bool = false
    @State private var errorMessage: String?
    @State private var extractionResult: BYOKExtractionResult?

    private let service = BYOKHolidayService()

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("将请假邮件、公司放假通知、国务院/MOM 政府公告文字或一句话指令粘贴到下方，直接在本地提取假期与调休补班。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $inputText)
                        .frame(minHeight: 130)
                        .padding(8)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    HStack(spacing: 10) {
                        Button {
                            runOfflineParse()
                        } label: {
                            Label("本地秒级解析 (零网络)", systemImage: "bolt.shield.fill")
                                .font(.footnote.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(Color.mint.opacity(0.22))
                                .foregroundStyle(.mint)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await runBYOKLLMParse() }
                        } label: {
                            HStack {
                                if isExtracting {
                                    ProgressView().controlSize(.small)
                                }
                                Label("BYOK LLM 深度提取", systemImage: "sparkles")
                                    .font(.footnote.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Color.orange.opacity(0.25))
                            .foregroundStyle(.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(isExtracting)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if let result = extractionResult {
                        extractedPreviewCard(result)
                    }
                }
                .padding(16)
            }
            .navigationTitle("BYOK 智能录入假期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
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
            // Fall back to offline parser while informing the user how to configure their own Key
            extractionResult = service.parseLocally(text: inputText)
            errorMessage = "提示：尚未在「设置」中配置 BYOK API Key，已自动使用本地规则完成解析。"
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

    private func extractedPreviewCard(_ result: BYOKExtractionResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(result.summaryNote)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.orange)

            if !result.entries.isEmpty {
                ForEach(result.entries) { entry in
                    HStack {
                        Text(entry.date)
                            .font(.caption.monospacedDigit().weight(.bold))
                        Text(entry.title)
                            .font(.caption)
                        Spacer()
                        Text(entry.kind.displayTitle)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(entry.kind == .makeupWorkday ? Color.orange.opacity(0.25) : Color.mint.opacity(0.25))
                            .clipShape(Capsule())
                    }
                }
            }

            if !result.discoveredCalendarURLs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("发现日历订阅链接 (.ics)：")
                        .font(.caption.weight(.semibold))
                    ForEach(result.discoveredCalendarURLs, id: \.self) { url in
                        Text(url)
                            .font(.caption2)
                            .foregroundStyle(.cyan)
                    }
                }
            }

            Button {
                viewModel.mergeExtractedEntries(result.entries, discoveredURLs: result.discoveredCalendarURLs)
                dismiss()
            } label: {
                Label("确认写入内置假期日历 (\(result.entries.count) 条)", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.green)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(result.entries.isEmpty && result.discoveredCalendarURLs.isEmpty)
        }
        .padding(14)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
