import SwiftUI
import VibeAlarmCore

/// Native Apple-style Holiday & Calendar Management View.
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
                // Section 1: External ICS Calendar Subscriptions
                Section {
                    ForEach(viewModel.snapshot.subscriptions) { sub in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(sub.name)
                                    .font(.body)
                                Spacer()
                                Text(sub.regionHint.rawValue)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Text(sub.url)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 2)
                        .swipeActions {
                            Button(role: .destructive) {
                                viewModel.removeSubscription(id: sub.id)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }

                    Button {
                        Task { await viewModel.syncExternalSubscriptions() }
                    } label: {
                        HStack {
                            Text(viewModel.isSyncingICS ? "正在更新订阅日历…" : "更新所有订阅日历")
                                .foregroundStyle(.orange)
                            Spacer()
                            if viewModel.isSyncingICS {
                                ProgressView()
                            }
                        }
                    }
                } header: {
                    Text("已订阅的公共假期日历 (.ics)")
                        .textCase(nil)
                }

                // Section 2: Add Custom ICS Subscription
                Section {
                    TextField("日历名称", text: $subName)
                    TextField("https:// 或 webcal:// 订阅链接", text: $subURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("地区", selection: $subRegion) {
                        ForEach(HolidayRegionHint.allCases, id: \.self) { r in
                            Text(r.displayName).tag(r)
                        }
                    }
                    Button("添加订阅源") {
                        guard !subURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        viewModel.addSubscription(
                            name: subName.isEmpty ? "自定义日历" : subName,
                            url: subURL,
                            region: subRegion
                        )
                        subName = ""
                        subURL = ""
                    }
                    .foregroundStyle(.orange)
                } header: {
                    Text("添加订阅")
                        .textCase(nil)
                }

                // Section 3: Quick Manual Add
                Section {
                    DatePicker("日期", selection: $manualDate, displayedComponents: .date)
                    TextField("备注（如：年假、春节调休补班）", text: $manualTitle)
                    Picker("类型", selection: $manualKind) {
                        ForEach(HolidayEntryKind.allCases, id: \.self) { kind in
                            Text(kind.displayTitle).tag(kind)
                        }
                    }
                    Button("添加日期记录") {
                        let dStr = AlarmScheduleEngine().dateString(from: manualDate)
                        let cleanTitle = manualTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        viewModel.addManualHolidayEntry(
                            date: dStr,
                            title: cleanTitle.isEmpty ? manualKind.displayTitle : cleanTitle,
                            kind: manualKind
                        )
                        manualTitle = ""
                    }
                    .foregroundStyle(.orange)
                } header: {
                    Text("手动添加假期或调休")
                        .textCase(nil)
                }

                // Section 4: Stored Holiday & Makeup Entries
                Section {
                    ForEach(viewModel.snapshot.holidayEntries) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title)
                                    .font(.body)
                                Text("\(entry.date) · \(entry.source.displayName)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(entry.kind.shortBadge)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(entry.kind == .makeupWorkday ? .orange : .secondary)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                viewModel.deleteHolidayEntry(entry)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("生效中的假期与调休 (\(viewModel.snapshot.holidayEntries.count))")
                        .textCase(nil)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("公共假期与调休")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(.orange)
                }
            }
        }
        .tint(.orange)
        .preferredColorScheme(.dark)
    }
}
