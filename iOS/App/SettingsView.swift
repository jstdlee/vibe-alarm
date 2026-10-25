import SwiftUI
import VibeAlarmCore

/// External Calendar Subscriptions (`.ics`) + iOS Calendar (`EventKit`) Access Settings + BYOK Keychain Settings (`日历源与权限设置` — Light Theme).
public struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    public var isEmbeddedInTab: Bool

    @State private var subNameInput: String = ""
    @State private var subURLInput: String = ""
    @State private var subRegionSelection: HolidayRegionHint = .custom

    @State private var apiKeyInput: String = ""
    @State private var provider: BYOKProviderKind = .openAICompatible
    @State private var endpointURL: String = ""
    @State private var modelName: String = ""
    @State private var keywordsText: String = ""
    @State private var savedKeyStatus: String?

    public init(viewModel: AppViewModel, isEmbeddedInTab: Bool = false) {
        self.viewModel = viewModel
        self.isEmbeddedInTab = isEmbeddedInTab
    }

    public var body: some View {
        NavigationStack {
            List {
                // SECTION 1: iOS SYSTEM CALENDAR ACCESS (EventKit 本地只读权限与日历源勾选)
                Section {
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("iOS 系统日历读取权限")
                                    .font(.subheadline.weight(.semibold))
                                Text(viewModel.localCalendarManager.statusDisplayText)
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        } icon: {
                            Image(systemName: "calendar.badge.checkmark")
                                .foregroundStyle(.orange)
                        }

                        Spacer()

                        Button {
                            Task { await viewModel.syncLocalCalendars() }
                        } label: {
                            Text("立即扫描")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.orange.opacity(0.14))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    // Selectable iOS Local Calendars (iCloud / Exchange / Local)
                    ForEach(viewModel.localCalendarManager.availableCalendars) { cal in
                        let isSelected = viewModel.snapshot.selectedLocalCalendarIDs.contains(cal.id)
                        Toggle(isOn: Binding(
                            get: { isSelected },
                            set: { enabled in
                                var copy = viewModel.snapshot
                                if enabled {
                                    if !copy.selectedLocalCalendarIDs.contains(cal.id) {
                                        copy.selectedLocalCalendarIDs.append(cal.id)
                                    }
                                } else {
                                    copy.selectedLocalCalendarIDs.removeAll { $0 == cal.id }
                                }
                                viewModel.applySnapshot(copy)
                            }
                        )) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(calendarDotColor(cal.colorHex))
                                    .frame(width: 9, height: 9)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(cal.title)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    Text("来源: \(cal.sourceTitle) · 自动识别请假/调休")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .tint(.green)
                    }

                    // Leave Keywords Row
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("请假匹配关键词")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("命中则自动跳过次日闹钟")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(viewModel.snapshot.leaveKeywords, id: \.self) { kw in
                                    Text(kw)
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.orange.opacity(0.12))
                                        .foregroundStyle(.orange)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("iOS 系统日历访问设置 (EventKit 本地只读)")
                        .textCase(nil)
                } footer: {
                    Text("仅在设备内存中只读匹配您勾选的 iOS 日历请假事件，日历数据 100% 不上传。")
                }

                // SECTION 2: EXTERNAL CALENDAR SUBSCRIPTIONS (.ics / webcal 外部公共假期日历订阅)
                Section {
                    ForEach(viewModel.snapshot.subscriptions) { sub in
                        Toggle(isOn: Binding(
                            get: { sub.isEnabled },
                            set: { enabled in
                                viewModel.toggleSubscription(id: sub.id, isEnabled: enabled)
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(sub.regionHint == .cn ? "🇨🇳" : (sub.regionHint == .sg ? "🇸🇬" : "🌐"))
                                    Text(sub.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                }
                                Text(sub.url)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .tint(.green)
                        .swipeActions {
                            Button(role: .destructive) {
                                viewModel.removeSubscription(id: sub.id)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }

                    // Add new external .ics subscription inline
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            TextField("新增外部日历名称", text: $subNameInput)
                                .font(.caption)
                                .padding(7)
                                .background(RoundedRectangle(cornerRadius: 7).fill(Color(uiColor: .systemGray6)))

                            TextField("https:// 或 webcal:// .ics 链接", text: $subURLInput)
                                .font(.caption)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(7)
                                .background(RoundedRectangle(cornerRadius: 7).fill(Color(uiColor: .systemGray6)))
                        }

                        HStack(spacing: 10) {
                            Button {
                                guard !subURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                                viewModel.addSubscription(
                                    name: subNameInput.isEmpty ? "外部公共假期 (.ics)" : subNameInput,
                                    url: subURLInput,
                                    region: subRegionSelection
                                )
                                subNameInput = ""
                                subURLInput = ""
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("添加外部 .ics 订阅")
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.orange)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button {
                                Task { await viewModel.syncExternalSubscriptions() }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                    Text(viewModel.isSyncingICS ? "同步中…" : "刷新全部外部日历")
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 3)
                } header: {
                    Text("外部公共假期日历订阅 (.ics / webcal)")
                        .textCase(nil)
                } footer: {
                    Text("支持订阅国务院法定节假日调休、新加坡 MOM 公共假期或任意标准 RFC 5545 .ics 日历链接。")
                }

                // SECTION 3: BYOK LLM & BEDTIME REMINDER
                Section {
                    HStack {
                        Text("BYOK 模型接口")
                            .font(.subheadline)
                        Spacer()
                        Text("\(provider.displayName) · \(modelName.isEmpty ? "gpt-4o-mini" : modelName)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                    }

                    HStack {
                        Text("API Key 钥匙串状态")
                            .font(.subheadline)
                        Spacer()
                        Text(apiKeyInput.isEmpty ? "已启用本地离线解析 (可填入 Key)" : "已加密存储于 iOS Keychain")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Toggle(
                        "每晚 \(viewModel.snapshot.alarmRule.formattedBedtimeReminder) 睡前确认通知",
                        isOn: Binding(
                            get: { viewModel.snapshot.alarmRule.bedtimeReminderEnabled },
                            set: { val in viewModel.updateAlarmRule { $0.bedtimeReminderEnabled = val } }
                        )
                    )
                    .font(.subheadline)
                    .tint(.green)
                } header: {
                    Text("BYOK 钥匙串与睡前确认提醒")
                        .textCase(nil)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("日历源与权限设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isEmbeddedInTab {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { dismiss() }
                            .foregroundStyle(.orange)
                    }
                }
            }
            .onAppear {
                loadInitialState()
            }
        }
        .tint(.orange)
        .preferredColorScheme(.light)
    }

    private func loadInitialState() {
        let cfg = viewModel.snapshot.byokConfig
        provider = cfg.provider
        endpointURL = cfg.endpointURL
        modelName = cfg.model
        apiKeyInput = KeychainHelper.loadAPIKey()
        keywordsText = viewModel.snapshot.leaveKeywords.joined(separator: ", ")
        viewModel.localCalendarManager.refreshAuthorizationStatus()
    }

    private func calendarDotColor(_ hex: String) -> Color {
        switch hex {
        case "#007AFF": return .blue
        case "#34C759": return .green
        case "#AF52DE": return .purple
        default: return .orange
        }
    }
}
