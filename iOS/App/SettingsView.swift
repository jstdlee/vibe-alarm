import SwiftUI
import VibeAlarmCore

/// Native Apple Settings-style sheet for:
/// - Pre-bedtime notification time & interactive preview
/// - Local EventKit Calendar selection & leave keywords (`请假 / 年假 / PTO / 休假`)
/// - BYOK LLM API Key (stored strictly in iOS Keychain), Provider, Endpoint & Model
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
                // Section 1: Pre-Bedtime Notification
                Section {
                    DatePicker(
                        "睡前提醒时间",
                        selection: $bedtimeDate,
                        displayedComponents: .hourAndMinute
                    )
                    .onChange(of: bedtimeDate) { _, newDate in
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                        let mins = (comps.hour ?? 22) * 60 + (comps.minute ?? 30)
                        viewModel.updateAlarmRule { $0.preBedtimeReminderMinutes = mins }
                    }

                    Button("发送睡前通知预览") {
                        Task { await viewModel.sendInstantBedtimePreviewNotification() }
                    }
                    .foregroundStyle(.orange)
                } header: {
                    Text("睡前确认通知")
                        .textCase(nil)
                } footer: {
                    Text("长按锁屏或通知中心的睡前提醒，可直接选择「跳过明日闹钟」或「推迟 30 分钟」。")
                }

                // Section 2: Local EventKit Calendar Integration
                Section {
                    HStack {
                        Text("匹配关键词")
                        Spacer()
                        TextField("请假, 年假, PTO", text: $keywordsText)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                            .onChange(of: keywordsText) { _, newValue in
                                let parts = newValue
                                    .split(separator: ",")
                                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                    .filter { !$0.isEmpty }
                                var copy = viewModel.snapshot
                                copy.leaveKeywords = parts
                                viewModel.applySnapshot(copy)
                            }
                    }

                    Button("读取系统日历中的请假日程") {
                        Task { await viewModel.syncLocalCalendars() }
                    }
                    .foregroundStyle(.orange)

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
                                        .foregroundStyle(.white)
                                    Spacer()
                                    if selected {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("系统日历 (EventKit)")
                        .textCase(nil)
                } footer: {
                    Text("仅在设备本地只读扫描全天或跨天请假事件，日程内容不会离开手机。")
                }

                // Section 3: BYOK LLM Configuration
                Section {
                    Picker("接口类型", selection: $provider) {
                        ForEach(BYOKProviderKind.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .onChange(of: provider) { _, newValue in
                        endpointURL = newValue.defaultEndpoint
                        modelName = newValue.defaultModel
                    }

                    HStack {
                        Text("接口地址")
                        Spacer()
                        TextField("URL", text: $endpointURL)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    HStack {
                        Text("模型")
                        Spacer()
                        TextField("gpt-4o-mini", text: $modelName)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    SecureField("API Key (存储在系统钥匙串)", text: $apiKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button("存储接口配置") {
                        saveBYOKSettings()
                    }
                    .foregroundStyle(.orange)

                    if let savedKeyStatus {
                        Text(savedKeyStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("自带密钥模型解析 (BYOK)")
                        .textCase(nil)
                } footer: {
                    Text("所有闹钟排期与日历数据均存储在本地 App Group 沙盒中，无云端服务器。API Key 加密保存在 iOS Keychain。")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(.orange)
                }
            }
            .onAppear {
                loadInitialState()
            }
        }
        .tint(.orange)
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
        savedKeyStatus = "已存储至 iOS 钥匙串"
    }
}
