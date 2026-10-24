import SwiftUI
import VibeAlarmCore

/// View for managing the built-in holiday & makeup workday calendar,
/// external `.ics` subscriptions (SG / CN / Custom), and manual holiday entries.
public struct HolidayCalendarView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var manualDate: Date = Date()
    @State private var manualTitle: String = ""
    @State private var manualKind: HolidayEntryKind = .personalLeave

    @State private var subName: String = ""
    @State private var subURL: String = ""
    @State private var subRegion: HolidayRegionHint = .custom

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            List {
                // Section 1: Quick Manual Add
                Section("手动添加假期 / 请假 / 调休补班") {
                    DatePicker("日期", selection: $manualDate, displayedComponents: .date)
                    TextField("名称（如：年假、春节调休补班）", text: $manualTitle)
                    Picker("类型", selection: $manualKind) {
                        ForEach(HolidayEntryKind.allCases, id: \.self) { kind in
                            Text(kind.displayTitle).tag(kind)
                        }
                    }
                    Button {
                        let dStr = AlarmScheduleEngine().dateString(from: manualDate)
                        let cleanTitle = manualTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        viewModel.addManualHolidayEntry(
                            date: dStr,
                            title: cleanTitle.isEmpty ? manualKind.displayTitle : cleanTitle,
                            kind: manualKind
                        )
                        manualTitle = ""
                    } label: {
                        Label("添加到内置假期日历", systemImage: "plus.circle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                // Section 2: External ICS Calendar Subscriptions
                Section("外部公共假期日历订阅 (.ics)") {
                    ForEach(viewModel.snapshot.subscriptions) { sub in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(sub.name)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(sub.regionHint.rawValue)
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.cyan.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                            Text(sub.url)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                viewModel.removeSubscription(id: sub.id)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        TextField("订阅名称（如：公司公共假期）", text: $subName)
                        TextField("https:// 或 webcal:// .ics 链接", text: $subURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Picker("地区预设", selection: $subRegion) {
                            ForEach(HolidayRegionHint.allCases, id: \.self) { r in
                                Text(r.displayName).tag(r)
                            }
                        }
                        Button {
                            guard !subURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            viewModel.addSubscription(
                                name: subName.isEmpty ? "自定义 ICS 订阅" : subName,
                                url: subURL,
                                region: subRegion
                            )
                            subName = ""
                            subURL = ""
                        } label: {
                            Label("添加 ICS 订阅源", systemImage: "link.badge.plus")
                        }
                    }

                    Button {
                        Task { await viewModel.syncExternalSubscriptions() }
                    } label: {
                        Label("立即拉取并更新所有 ICS 订阅", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.cyan)
                    }
                }

                // Section 3: Stored Holiday & Makeup Entries
                Section("已生效假期与调休条目 (\(viewModel.snapshot.holidayEntries.count))") {
                    ForEach(viewModel.snapshot.holidayEntries) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(entry.date) · \(entry.title)")
                                    .font(.subheadline.weight(.medium))
                                Text("来源：\(entry.source.displayName)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(entry.kind.shortBadge)
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    entry.kind == .makeupWorkday
                                        ? Color.orange.opacity(0.25)
                                        : Color.mint.opacity(0.22)
                                )
                                .foregroundStyle(entry.kind == .makeupWorkday ? .orange : .mint)
                                .clipShape(Capsule())
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                viewModel.deleteHolidayEntry(entry)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("内置假期与订阅管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
