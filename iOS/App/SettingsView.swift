import SwiftUI
import VibeAlarmCore

/// Screen 4 ("Sources"): Braun/Apple Light Theme calendar sources & BYOK settings.
/// Three clean cards: iOS Calendar access (EventKit), external `.ics` subscriptions,
/// and the on-device AI parser + bedtime confirmation.
public struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var subNameInput: String = ""
    @State private var subURLInput: String = ""

    @State private var newKeywordInput: String = ""
    @State private var apiKeyInput: String = ""
    @State private var provider: BYOKProviderKind = .openAICompatible
    @State private var modelName: String = ""
    @State private var endpointURL: String = ""
    @State private var savedKeyStatus: String?

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    header
                    eventKitCard
                    externalCalendarsCard
                    byokAndBedtimeCard
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .background(Color.vibeCanvas)
            .navigationBarHidden(true)
            .onAppear {
                loadInitialState()
            }
        }
        .tint(.vibeAccent)
        .preferredColorScheme(.light)
    }

    private var header: some View {
        Text("Sources")
            .font(.system(size: 26, weight: .bold, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 1. iOS Calendar Access (EventKit)

    private var eventKitCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader("iOS CALENDAR ACCESS (EVENTKIT)")

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.localCalendarManager.statusDisplayText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Read-only · never leaves this device")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await viewModel.syncLocalCalendars() }
                } label: {
                    Text("Scan Now")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.vibeAccent.opacity(0.14))
                        .foregroundStyle(.vibeAccent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 0) {
                ForEach(viewModel.localCalendarManager.availableCalendars) { cal in
                    let isSelected = viewModel.snapshot.selectedLocalCalendarIDs.contains(cal.id)
                    Button {
                        var copy = viewModel.snapshot
                        if isSelected {
                            copy.selectedLocalCalendarIDs.removeAll { $0 == cal.id }
                        } else {
                            copy.selectedLocalCalendarIDs.append(cal.id)
                        }
                        viewModel.applySnapshot(copy)
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(calendarDotColor(cal.colorHex))
                                .frame(width: 8, height: 8)
                            Text("\(cal.title) · \(cal.sourceTitle)")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.vibeAccent)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("LEAVE KEYWORDS")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)

                FlowChips(items: viewModel.snapshot.leaveKeywords) { keyword in
                    viewModel.removeLeaveKeyword(keyword)
                }

                HStack(spacing: 8) {
                    TextField("+ Keyword", text: $newKeywordInput)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(uiColor: .systemGray6)))
                    Button {
                        viewModel.addLeaveKeyword(newKeywordInput)
                        newKeywordInput = ""
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.vibeAccent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .vibeCard()
    }

    // MARK: - 2. External Calendars (.ics)

    private var externalCalendarsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader("EXTERNAL CALENDARS (.ICS)")

            VStack(spacing: 0) {
                ForEach(viewModel.snapshot.subscriptions) { sub in
                    HStack {
                        Toggle(isOn: Binding(
                            get: { sub.isEnabled },
                            set: { enabled in viewModel.toggleSubscription(id: sub.id, isEnabled: enabled) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sub.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text(hostLabel(for: sub.url))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .tint(.vibeAccent)
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
            }

            HStack(spacing: 8) {
                TextField("Calendar name", text: $subNameInput)
                    .font(.caption)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(uiColor: .systemGray6)))
                TextField("https:// or webcal:// .ics link", text: $subURLInput)
                    .font(.caption)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(uiColor: .systemGray6)))
            }

            HStack {
                Button {
                    guard !subURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    viewModel.addSubscription(
                        name: subNameInput.isEmpty ? "External Calendar (.ics)" : subNameInput,
                        url: subURLInput,
                        region: .custom
                    )
                    subNameInput = ""
                    subURLInput = ""
                } label: {
                    Text("+ Add .ics Feed")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.vibeAccent)
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
                        Text(viewModel.isSyncingICS ? "Syncing…" : "Refresh All")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.vibeAccent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .vibeCard()
    }

    // MARK: - 3. On-Device AI Parser (BYOK) & Bedtime

    private var byokAndBedtimeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader("ON-DEVICE AI PARSER (BYOK) & BEDTIME")

            Picker("Provider", selection: $provider) {
                Text("OpenAI Compatible").tag(BYOKProviderKind.openAICompatible)
                Text("Anthropic Claude").tag(BYOKProviderKind.anthropic)
            }
            .pickerStyle(.segmented)
            .onChange(of: provider) { _, newValue in
                endpointURL = newValue.defaultEndpoint
                modelName = newValue.defaultModel
                persistBYOKConfig()
            }

            labeledField(label: "Model", text: $modelName, placeholder: "gpt-4o-mini")
            labeledField(label: "Endpoint", text: $endpointURL, placeholder: provider.defaultEndpoint)

            HStack {
                Text("API Key")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .leading)
                SecureField("Paste API Key", text: $apiKeyInput)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color(uiColor: .systemGray6)))
                Button("Save") {
                    _ = KeychainHelper.saveAPIKey(apiKeyInput)
                    savedKeyStatus = apiKeyInput.isEmpty ? "Cleared" : "Saved to Keychain"
                    persistBYOKConfig()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.vibeAccent)
            }

            Text(savedKeyStatus ?? (apiKeyInput.isEmpty ? "Not set · using on-device parser" : "Stored in iOS Keychain"))
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bedtime Confirmation")
                        .font(.subheadline.weight(.medium))
                    Text(viewModel.snapshot.alarmRule.formattedBedtimeReminder)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer()
                DatePicker(
                    "Bedtime Time",
                    selection: bedtimeDateBinding,
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                Toggle("", isOn: Binding(
                    get: { viewModel.snapshot.alarmRule.bedtimeReminderEnabled },
                    set: { val in viewModel.updateAlarmRule { $0.bedtimeReminderEnabled = val } }
                ))
                .labelsHidden()
                .tint(.vibeAccent)
            }
        }
        .padding(16)
        .vibeCard()
    }

    private func labeledField(label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            TextField(placeholder, text: text)
                .font(.caption)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color(uiColor: .systemGray6)))
        }
    }

    private func cardHeader(_ caption: String) -> some View {
        Text(caption)
            .font(.system(size: 11, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(.secondary)
    }

    private var bedtimeDateBinding: Binding<Date> {
        Binding(
            get: {
                let minutes = viewModel.snapshot.alarmRule.preBedtimeReminderMinutes
                var comps = DateComponents()
                comps.hour = minutes / 60
                comps.minute = minutes % 60
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                let minutes = (comps.hour ?? 22) * 60 + (comps.minute ?? 30)
                viewModel.updateAlarmRule { $0.preBedtimeReminderMinutes = minutes }
            }
        )
    }

    private func loadInitialState() {
        let cfg = viewModel.snapshot.byokConfig
        provider = cfg.provider
        endpointURL = cfg.endpointURL
        modelName = cfg.model
        apiKeyInput = KeychainHelper.loadAPIKey()
        viewModel.localCalendarManager.refreshAuthorizationStatus()
    }

    private func persistBYOKConfig() {
        viewModel.updateBYOKConfig(
            BYOKConfiguration(provider: provider, endpointURL: endpointURL, model: modelName)
        )
    }

    private func hostLabel(for urlString: String) -> String {
        URL(string: urlString)?.host ?? urlString
    }

    private func calendarDotColor(_ hex: String) -> Color {
        switch hex {
        case "#007AFF": return .vibeWork
        case "#34C759": return .vibePTO
        case "#AF52DE": return .purple
        default: return .vibeAccent
        }
    }
}

/// Simple wrapping chip row for leave keywords with a tap-to-remove affordance.
private struct FlowChips: View {
    let items: [String]
    let onRemove: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    HStack(spacing: 4) {
                        Text(item)
                            .font(.caption.weight(.medium))
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.vibeAccent.opacity(0.12))
                    .foregroundStyle(.vibeAccent)
                    .clipShape(Capsule())
                    .onTapGesture {
                        onRemove(item)
                    }
                }
            }
        }
    }
}
