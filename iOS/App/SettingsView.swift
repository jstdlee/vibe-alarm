import SwiftUI
import VibeAlarmCore

/// Settings view for:
/// - BYOK LLM API Key (stored strictly in iOS Keychain), Provider, Endpoint & Model
/// - Local EventKit Calendar selection & leave keywords (`请假 / 年假 / PTO / 休假`)
/// - Pre-bedtime notification time & interactive preview
/// - 100% On-Device Privacy Architecture overview
public struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var apiKeyInput: String = ""
    @State private var provider: BYOKProviderKind = .openAICompatible
    @State private var endpointURL: String = ""
    @State private var modelName: String = ""
    @State private var keywordsText: String = ""
    @State private var bedtimeDate: Date = Date()
    @State private var savedKeyStatus: String?

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            Form {
                // Section 1: Privacy Guarantee
                Section("隐私优先 · 100% 本地架构") {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("零后端 API · 零集中式 Agent · 数据完全自主掌控", systemImage: "lock.shield.fill")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.mint)
                        Text("• 闹钟排期、节假日判断与次日恢复全部在 iPhone 本地沙盒 (App Group) 完成。\n• 本地日历 (EventKit) 仅在设备端只读匹配请假关键词，绝不上传。\n• BYOK API Key 仅保存在 iOS 系统钥匙串 (Keychain)，由手机直连你选择的模型接口。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // Section 2: BYOK LLM Configuration
                Section("BYOK LLM 接口配置 (Keychain 加密存储)") {
                    Picker("接口协议", selection: $provider) {
                        ForEach(BYOKProviderKind.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .onChange(of: provider) { _, newValue in
                        endpointURL = newValue.defaultEndpoint
                        modelName = newValue.defaultModel
                    }

                    TextField("API Endpoint URL", text: $endpointURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("模型名称 (如 gpt-4o-mini / deepseek-chat)", text: $modelName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("API Key (仅存入本地 iOS Keychain)", text: $apiKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button {
                        saveBYOKSettings()
                    } label: {
                        Label("保存 BYOK 配置与 Keychain 密钥", systemImage: "key.fill")
                            .foregroundStyle(.orange)
                    }

                    if let savedKeyStatus {
                        Text(savedKeyStatus)
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }

                // Section 3: Local EventKit Calendar Integration
                Section("本地系统日历读取 (EventKit)") {
                    TextField("请假识别关键词 (逗号分隔)", text: $keywordsText)
                        .onChange(of: keywordsText) { _, newValue in
                            let parts = newValue
                                .split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                            var copy = viewModel.snapshot
                            copy.leaveKeywords = parts
                            viewModel.applySnapshot(copy)
                        }

                    Button {
                        Task { await viewModel.syncLocalCalendars() }
                    } label: {
                        Label("授权并扫描本地日历中的个人休假", systemImage: "calendar.badge.checkmark")
                            .foregroundStyle(.mint)
                    }

                    if !viewModel.localCalendarManager.availableCalendars.isEmpty {
                        ForEach(viewModel.localCalendarManager.availableCalendars) { cal in
                            let selected = viewModel.snapshot.selectedLocalCalendarIDs.contains(cal.id)
                            Button {
                                var copy = viewModel.snapshot
                                if selected {
                                    copy.selectedLocalCalendarIDs.removeAll { $0 == cal.id }
                                } else {
                                    copy.selectedLocalCalendarIDs.append(cal.id)
                                }
                                viewModel.applySnapshot(copy)
                            } label: {
                                HStack {
                                    Text("\(cal.title) (\(cal.sourceTitle))")
                                        .font(.caption)
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selected ? .mint : .secondary)
                                }
                            }
                        }
                    }
                }

                // Section 4: Pre-Bedtime Notification
                Section("睡前提醒通知 & 快捷操作测试") {
                    DatePicker(
                        "每晚提醒时间",
                        selection: $bedtimeDate,
                        displayedComponents: .hourAndMinute
                    )
                    .onChange(of: bedtimeDate) { _, newDate in
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                        let mins = (comps.hour ?? 22) * 60 + (comps.minute ?? 30)
                        viewModel.updateAlarmRule { $0.preBedtimeReminderMinutes = mins }
                    }

                    Button {
                        Task { await viewModel.sendInstantBedtimePreviewNotification() }
                    } label: {
                        Label("发送睡前可交互通知预览 (2秒后弹出)", systemImage: "bell.badge.waveform.fill")
                            .foregroundStyle(.cyan)
                    }
                }
            }
            .navigationTitle("BYOK 与隐私设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                loadInitialState()
            }
        }
        .preferredColorScheme(.dark)
    }

    private func loadInitialState() {
        let cfg = viewModel.snapshot.byokConfig
        provider = cfg.provider
        endpointURL = cfg.endpointURL
        modelName = cfg.model
        apiKeyInput = KeychainHelper.loadAPIKey()
        keywordsText = viewModel.snapshot.leaveKeywords.joined(separator: ", ")

        let mins = viewModel.snapshot.alarmRule.preBedtimeReminderMinutes
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = mins / 60
        comps.minute = mins % 60
        if let d = Calendar.current.date(from: comps) {
            bedtimeDate = d
        }
        viewModel.localCalendarManager.refreshAuthorizationStatus()
    }

    private func saveBYOKSettings() {
        var copy = viewModel.snapshot
        copy.byokConfig = BYOKConfiguration(
            provider: provider,
            endpointURL: endpointURL.trimmingCharacters(in: .whitespacesAndNewlines),
            model: modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        viewModel.applySnapshot(copy)
        _ = KeychainHelper.saveAPIKey(apiKeyInput)
        savedKeyStatus = "已保存配置并将 API Key 加密写入 iOS Keychain"
    }
}
