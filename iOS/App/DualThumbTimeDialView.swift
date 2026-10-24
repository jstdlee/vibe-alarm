import SwiftUI
import UIKit
import VibeAlarmCore

/// Native Apple Clock ("编辑闹钟") Modal Sheet featuring the ergonomic Dual-Thumb Drum Picker:
/// - Left column: Left thumb vertical drum wheel for Hour (`00`–`23`)
/// - Right column: Right thumb vertical drum wheel for Minute (`00`–`59`)
/// - Signature iOS center selection highlight bar (`tertiarySystemFill`, cornerRadius 8)
/// - Below: Standard iOS `.insetGrouped` Form rows for Repeat Mode, Specific Dates, Label, and Smart Holiday Switches.
public struct DualThumbTimeDialSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            DualThumbTimeDialView(viewModel: viewModel)
                .navigationTitle("编辑闹钟")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") {
                            dismiss()
                        }
                        .foregroundStyle(.orange)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("存储") {
                            dismiss()
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                    }
                }
        }
        .tint(.orange)
        .preferredColorScheme(.dark)
    }
}

public struct DualThumbTimeDialView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var newSpecificDate: Date = Date()

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        List {
            // Section 1: Apple Drum-Style Dual-Thumb Picker
            Section {
                VStack(spacing: 12) {
                    ZStack {
                        // Signature Apple Picker Center Selection Highlight Bar
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemFill))
                            .frame(height: 38)

                        HStack(spacing: 0) {
                            AppleDrumColumn(
                                value: viewModel.snapshot.alarmRule.hour,
                                modulo: 24,
                                unitLabel: "时"
                            ) { newHour in
                                viewModel.updateAlarmTime(
                                    hour: newHour,
                                    minute: viewModel.snapshot.alarmRule.minute
                                )
                            }

                            AppleDrumColumn(
                                value: viewModel.snapshot.alarmRule.minute,
                                modulo: 60,
                                unitLabel: "分"
                            ) { newMinute in
                                viewModel.updateAlarmTime(
                                    hour: viewModel.snapshot.alarmRule.hour,
                                    minute: newMinute
                                )
                            }
                        }
                    }
                    .frame(height: 196)
                }
                .padding(.vertical, 4)
            } footer: {
                Text("左右分栏滚轮支持双手拇指分别上下滑动调节「时」与「分」。")
            }

            // Section 2: Repeat & Date Rules (下方设定重复和日期)
            Section {
                Picker("重复", selection: Binding(
                    get: { repeatModeTag },
                    set: { newTag in
                        switch newTag {
                        case 0:
                            viewModel.updateAlarmRule { $0.repeatMode = .weekdays }
                        case 1:
                            viewModel.updateAlarmRule { $0.repeatMode = .everyday }
                        case 2:
                            viewModel.updateAlarmRule { $0.repeatMode = .customDays(Weekday.standardWeekdays) }
                        case 3:
                            let tomorrowStr = viewModel.tomorrowAlarm.date
                            viewModel.updateAlarmRule { $0.repeatMode = .specificDates([tomorrowStr]) }
                        default:
                            break
                        }
                    }
                )) {
                    Text("法定工作日").tag(0)
                    Text("每天").tag(1)
                    Text("自定义星期").tag(2)
                    Text("指定日期").tag(3)
                }

                if case .customDays(let selectedDays) = viewModel.snapshot.alarmRule.repeatMode {
                    HStack(spacing: 6) {
                        ForEach([Weekday.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday], id: \.self) { day in
                            let active = selectedDays.contains(day)
                            Button {
                                triggerHaptic()
                                var next = selectedDays
                                if active {
                                    next.remove(day)
                                } else {
                                    next.insert(day)
                                }
                                viewModel.updateAlarmRule { $0.repeatMode = .customDays(next) }
                            } label: {
                                Text(day.compactLabel)
                                    .font(.subheadline.weight(.medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 7)
                                    .background(active ? Color.orange : Color(uiColor: .tertiarySystemFill))
                                    .foregroundStyle(active ? Color.black : Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }

                if case .specificDates(let dates) = viewModel.snapshot.alarmRule.repeatMode {
                    HStack {
                        DatePicker(
                            "添加日期",
                            selection: $newSpecificDate,
                            displayedComponents: .date
                        )
                        Spacer()
                        Button("添加") {
                            triggerHaptic()
                            let dStr = AlarmScheduleEngine().dateString(from: newSpecificDate)
                            var next = dates
                            next.insert(dStr)
                            viewModel.updateAlarmRule { $0.repeatMode = .specificDates(next) }
                        }
                        .foregroundStyle(.orange)
                    }

                    ForEach(dates.sorted(), id: \.self) { dStr in
                        HStack {
                            Text(dStr)
                                .font(.body.monospacedDigit())
                            Spacer()
                            Button(role: .destructive) {
                                var next = dates
                                next.remove(dStr)
                                viewModel.updateAlarmRule { $0.repeatMode = .specificDates(next) }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack {
                    Text("标签")
                    Spacer()
                    TextField("起床", text: Binding(
                        get: { viewModel.snapshot.alarmRule.label },
                        set: { val in viewModel.updateAlarmRule { $0.label = val } }
                    ))
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                }
            }

            // Section 3: Smart Holiday & Bedtime Settings
            Section {
                Toggle("法定节假日跳过 & 调休补班响铃", isOn: Binding(
                    get: { viewModel.snapshot.alarmRule.skipPublicHolidays },
                    set: { val in viewModel.updateAlarmRule { $0.skipPublicHolidays = val } }
                ))
                .tint(.green)

                Toggle("个人休假自动跳过", isOn: Binding(
                    get: { viewModel.snapshot.alarmRule.skipPersonalLeave },
                    set: { val in viewModel.updateAlarmRule { $0.skipPersonalLeave = val } }
                ))
                .tint(.green)

                Toggle("睡前确认提醒 (\(viewModel.snapshot.alarmRule.formattedBedtimeReminder))", isOn: Binding(
                    get: { viewModel.snapshot.alarmRule.bedtimeReminderEnabled },
                    set: { val in viewModel.updateAlarmRule { $0.bedtimeReminderEnabled = val } }
                ))
                .tint(.green)
            } header: {
                Text("智能假期规则")
                    .textCase(nil)
            } footer: {
                Text("开启后自动识别公共假期、周末调休补班及本地日历中的请假日程。")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var repeatModeTag: Int {
        switch viewModel.snapshot.alarmRule.repeatMode {
        case .weekdays: return 0
        case .everyday: return 1
        case .customDays: return 2
        case .specificDates: return 3
        }
    }

    private func triggerHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}

// MARK: - Apple Native-Style Drum Wheel Column

private struct AppleDrumColumn: View {
    let value: Int
    let modulo: Int
    let unitLabel: String
    let onChange: (Int) -> Void

    @State private var dragStartValue: Int?
    @State private var visualOffset: CGFloat = 0

    private let stepHeight: CGFloat = 28

    var body: some View {
        ZStack {
            VStack(spacing: 4) {
                ForEach([-3, -2, -1, 0, 1, 2, 3], id: \.self) { delta in
                    let slotVal = wrapped(value + delta)
                    let isCenter = delta == 0
                    let distance = CGFloat(abs(delta))

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%02d", slotVal))
                            .font(.system(
                                size: isCenter ? 24 : 21,
                                weight: isCenter ? .regular : .regular
                            ))
                            .monospacedDigit()
                            .foregroundStyle(
                                isCenter
                                    ? Color.white
                                    : Color.white.opacity(max(0.15, 0.65 - distance * 0.18))
                            )
                        if isCenter {
                            Text(unitLabel)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(unitLabel)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(.clear)
                        }
                    }
                    .rotation3DEffect(
                        .degrees(Double(delta) * -18),
                        axis: (x: 1, y: 0, z: 0),
                        perspective: 0.4
                    )
                    .scaleEffect(isCenter ? 1.0 : max(0.82, 1.0 - distance * 0.06))
                    .frame(height: 24)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard delta != 0 else { return }
                        emitTick(newValue: slotVal)
                    }
                }
            }
            .offset(y: visualOffset * 0.25)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { gesture in
                    if dragStartValue == nil {
                        dragStartValue = value
                    }
                    let base = dragStartValue ?? value
                    let steps = Int((-gesture.translation.height / stepHeight).rounded())
                    let candidate = wrapped(base + steps)
                    visualOffset = gesture.translation.height.truncatingRemainder(dividingBy: stepHeight)
                    if candidate != value {
                        emitTick(newValue: candidate)
                    }
                }
                .onEnded { _ in
                    dragStartValue = nil
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.78)) {
                        visualOffset = 0
                    }
                }
        )
    }

    private func wrapped(_ raw: Int) -> Int {
        ((raw % modulo) + modulo) % modulo
    }

    private func emitTick(newValue: Int) {
        let gen = UISelectionFeedbackGenerator()
        gen.selectionChanged()
        onChange(newValue)
    }
}
