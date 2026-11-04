import SwiftUI
import UIKit
import VibeAlarmCore

/// The Sources tab: what the alarm listens to, and nothing else.
///
/// The page is one column of paper with engraved hairlines between rows. Sections are separated
/// by space and a short caption, never by a card. Anything that is simply on or off is a Toggle;
/// the only value that needs choosing with a control other than a switch is the snooze interval,
/// and it uses the same roller as the wake time editor.
public struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var apiKeyInput: String = ""
    @State private var provider: BYOKProviderKind = .openAICompatible
    @State private var modelName: String = ""
    @State private var endpointURL: String = ""
    @State private var byokStatusMessage: String?
    @State private var showAddCountrySheet = false
    @State private var showAddSubscriptionSheet = false
    @State private var showSnoozeRoller = false
    @State private var showBYOKDetails = false

    private let snoozeOptions: [String] = AlarmRule.snoozeIntervalOptions.map { "\($0) min" }

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("VIBE ALARM")
                        .vibeCaption()
                        .padding(.top, 14)
                    Text("Sources")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(VibePalette.ink)
                        .padding(.top, 6)

                    section("Holiday Calendars", top: 34) {
                        holidayCalendarRows
                    }

                    section("iOS Calendar", top: 34) {
                        iOSCalendarRows
                    }

                    section("Reminders", top: 34) {
                        reminderRows
                    }

                    section("AI Import", top: 34) {
                        byokRows
                    }

                    privacyFooter
                        .padding(.top, 36)
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 120)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(VibePalette.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { loadInitialState() }
            .sheet(isPresented: $showAddCountrySheet) {
                HolidayCatalogSearchSheet(viewModel: viewModel)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showAddSubscriptionSheet) {
                AddSubscriptionSheet(viewModel: viewModel)
            }
        }
        .tint(VibePalette.amber)
    }

    // MARK: - Section Frame

    private func section<Content: View>(
        _ caption: String,
        top: CGFloat = 28,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(caption.uppercased())
                .vibeCaption()
                .padding(.bottom, 10)
            Hairline()
            content()
        }
        .padding(.top, top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Row Frame

    /// A row on paper: label on the left, optional value on the right, hairline below. Rows carry
    /// no background of their own, so a section reads as a list of lines rather than a stack of
    /// cards.
    private func row<Content: View>(
        _ title: String,
        detail: String? = nil,
        @ViewBuilder accessory: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(VibePalette.ink)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 11.5))
                            .foregroundStyle(VibePalette.inkFaint)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                accessory()
            }
            .padding(.vertical, 14)
            Hairline()
        }
    }

    /// A row whose whole surface is a button, used for anything that pushes or opens a sheet.
    private func linkRow(_ title: String, detail: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            row(title, detail: detail) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VibePalette.inkFaint.opacity(0.8))
            }
        }
        .buttonStyle(.plain)
    }

    private func valueText(_ text: String, active: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(active ? VibePalette.amber : VibePalette.inkFaint)
    }

    // MARK: - Holiday Calendars

    private var holidayCalendarRows: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.snapshot.subscriptions) { sub in
                subscriptionRow(sub)
            }

            linkRow(
                "Add Country",
                detail: "\(HolidayCatalog.all.count) public holiday feeds, searchable"
            ) {
                showAddCountrySheet = true
            }

            linkRow("Add Custom URL") {
                showAddSubscriptionSheet = true
            }

            row(
                "Refresh All",
                detail: lastRefreshDetail
            ) {
                Button {
                    Task { await viewModel.syncExternalSubscriptions() }
                } label: {
                    valueText(viewModel.isSyncingICS ? "Syncing" : "Refresh", active: viewModel.isSyncingICS)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSyncingICS)
            }
        }
    }

    private func subscriptionRow(_ sub: ExternalCalendarSubscription) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(sub.name)
                        .font(.system(size: 15, weight: sub.isEnabled ? .regular : .light))
                        .foregroundStyle(sub.isEnabled ? VibePalette.ink : VibePalette.inkFaint)
                        .lineLimit(1)
                    Text(URL(string: sub.url)?.host ?? sub.url)
                        .font(.system(size: 11.5))
                        .foregroundStyle(VibePalette.inkFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(
                    get: { sub.isEnabled },
                    set: { viewModel.toggleSubscription(id: sub.id, isEnabled: $0) }
                ))
                .labelsHidden()
                .tint(VibePalette.amber)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .contextMenu {
                Button(role: .destructive) {
                    viewModel.removeSubscription(id: sub.id)
                } label: {
                    Label("Remove Calendar", systemImage: "trash")
                }
            }
            Hairline()
        }
    }

    private var lastRefreshDetail: String {
        guard let latest = viewModel.snapshot.subscriptions.compactMap(\.lastSyncedAt).max() else {
            return "Never synced"
        }
        return "Last synced \(Self.timeFormatter.string(from: latest))"
    }

    // MARK: - iOS Calendar

    private var iOSCalendarRows: some View {
        VStack(spacing: 0) {
            row("Access", detail: "Read-only. Events never leave this iPhone.") {
                valueText(viewModel.localCalendarManager.accessStatusLabel)
            }

            if viewModel.localCalendarManager.hasReadAccess {
                ForEach(viewModel.localCalendarManager.availableCalendars) { cal in
                    row(cal.title) {
                        Toggle("", isOn: Binding(
                            get: { viewModel.snapshot.selectedLocalCalendarIDs.contains(cal.id) },
                            set: { isOn in
                                var copy = viewModel.snapshot
                                if isOn {
                                    copy.selectedLocalCalendarIDs.append(cal.id)
                                } else {
                                    copy.selectedLocalCalendarIDs.removeAll { $0 == cal.id }
                                }
                                viewModel.applySnapshot(copy)
                            }
                        ))
                        .labelsHidden()
                        .tint(VibePalette.amber)
                    }
                }
            } else if viewModel.localCalendarManager.authorizationStatus == .denied
                        || viewModel.localCalendarManager.authorizationStatus == .restricted {
                linkRow("Open iOS Settings") { openSystemSettings() }
            } else {
                linkRow("Grant Access") {
                    Task { _ = await viewModel.localCalendarManager.requestAccess() }
                }
            }

            linkRow(
                "Leave Keywords",
                detail: "\(viewModel.snapshot.leaveKeywords.count) keywords mark personal leave"
            ) {
                showLeaveKeywords = true
            }

            row("Scan Now", detail: lastScanDetail) {
                Button {
                    Task { await viewModel.syncLocalCalendars() }
                } label: {
                    valueText("Scan")
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showLeaveKeywords) {
            NavigationStack { LeaveKeywordsEditorView(viewModel: viewModel) }
        }
    }

    @State private var showLeaveKeywords = false

    private var lastScanDetail: String {
        guard let lastScan = viewModel.lastLocalCalendarScanAt else { return "Not scanned yet" }
        return "Last scanned \(Self.timeFormatter.string(from: lastScan))"
    }

    // MARK: - Reminders

    private var reminderRows: some View {
        VStack(spacing: 0) {
            row("Snooze Interval", detail: "Used by the notification action and the wake alarm.") {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { showSnoozeRoller.toggle() }
                } label: {
                    valueText("\(viewModel.snoozeMinutes) min", active: showSnoozeRoller)
                }
                .buttonStyle(.plain)
            }

            if showSnoozeRoller {
                CompactRoller(
                    caption: "Snooze",
                    options: snoozeOptions,
                    selectedIndex: snoozeIndex
                ) { idx in
                    selectSnoozeIndex(idx)
                }
                .padding(.vertical, 12)
            }
        }
    }

    private var snoozeIndex: Int {
        AlarmRule.snoozeIntervalOptions.firstIndex(of: viewModel.snoozeMinutes) ?? 0
    }

    private func selectSnoozeIndex(_ idx: Int) {
        guard AlarmRule.snoozeIntervalOptions.indices.contains(idx) else { return }
        viewModel.setSnoozeMinutes(AlarmRule.snoozeIntervalOptions[idx])
    }

    // MARK: - AI Import

    private var byokRows: some View {
        VStack(spacing: 0) {
            row("Key on Device", detail: KeychainHelper.loadAPIKey().isEmpty
                ? "No key stored. Paste notices by hand instead."
                : "Stored in the iOS Keychain.") {
                Toggle("", isOn: Binding(
                    get: { showBYOKDetails },
                    set: { withAnimation(.easeInOut(duration: 0.22)) { showBYOKDetails = $0 } }
                ))
                .labelsHidden()
                .tint(VibePalette.amber)
            }

            if showBYOKDetails {
                byokDetails
            }
        }
    }

    private var byokDetails: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Provider", selection: $provider) {
                Text("OpenAI Compatible").tag(BYOKProviderKind.openAICompatible)
                Text("Anthropic").tag(BYOKProviderKind.anthropic)
            }
            .pickerStyle(.segmented)
            .onChange(of: provider) { _, newValue in
                endpointURL = newValue.defaultEndpoint
                modelName = newValue.defaultModel
                persistBYOKConfig()
            }

            fieldRow("Base URL", text: $endpointURL, prompt: "https://", isSecure: false)
            fieldRow("Model", text: $modelName, prompt: "Model", isSecure: false)
            fieldRow("API Key", text: $apiKeyInput, prompt: "Required", isSecure: true)

            HStack(spacing: 14) {
                Button {
                    Task {
                        saveAPIKey()
                        byokStatusMessage = await viewModel.testBYOKConnection()
                    }
                } label: {
                    Text("TEST CONNECTION")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(VibePalette.amber)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .machinedPlate(corner: 14)
                }
                .buttonStyle(KeyPressStyle())
                .disabled(viewModel.isTestingBYOKConnection)

                Button {
                    saveAPIKey()
                    byokStatusMessage = "Key saved to the Keychain."
                } label: {
                    Text("SAVE KEY")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(VibePalette.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .machinedPlate(corner: 14)
                }
                .buttonStyle(KeyPressStyle())
            }

            if let byokStatusMessage {
                Text(byokStatusMessage)
                    .font(.system(size: 11.5))
                    .foregroundStyle(VibePalette.inkFaint)
                    .lineSpacing(2)
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private func fieldRow(
        _ title: String,
        text: Binding<String>,
        prompt: String,
        isSecure: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .vibeCaption()
            Group {
                if isSecure {
                    SecureField(prompt, text: text)
                } else {
                    TextField(prompt, text: text)
                }
            }
            .font(.system(size: 13, design: .monospaced))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .foregroundStyle(VibePalette.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .recessedWell(corner: 12)
            .onSubmit { persistBYOKConfig() }
        }
    }

    // MARK: - Privacy

    private var privacyFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Hairline()
                .padding(.bottom, 4)
            Text("Everything stays on this iPhone. No account, no server, no analytics.")
                .font(.system(size: 11.5))
                .lineSpacing(3)
                .foregroundStyle(VibePalette.inkFaint)
        }
    }

    // MARK: - Actions

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func saveAPIKey() {
        _ = KeychainHelper.saveAPIKey(apiKeyInput)
        persistBYOKConfig()
    }

    private func loadInitialState() {
        let cfg = viewModel.snapshot.byokConfig
        provider = cfg.provider
        endpointURL = cfg.endpointURL
        modelName = cfg.model
        apiKeyInput = KeychainHelper.loadAPIKey()
        showBYOKDetails = !apiKeyInput.isEmpty
        viewModel.localCalendarManager.refreshAuthorizationStatus()
    }

    private func persistBYOKConfig() {
        viewModel.updateBYOKConfig(
            BYOKConfiguration(provider: provider, endpointURL: endpointURL, model: modelName)
        )
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - Leave Keywords Editor

public struct LeaveKeywordsEditorView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var newKeyword: String = ""

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Events in your own calendars whose title or notes contain one of these words are treated as personal leave.")
                    .font(.system(size: 12))
                    .lineSpacing(3)
                    .foregroundStyle(VibePalette.inkFaint)
                    .padding(.bottom, 18)

                Hairline()
                ForEach(viewModel.snapshot.leaveKeywords, id: \.self) { keyword in
                    VStack(spacing: 0) {
                        HStack {
                            Text(keyword)
                                .font(.system(size: 15))
                                .foregroundStyle(VibePalette.ink)
                            Spacer()
                            Button {
                                viewModel.removeLeaveKeyword(keyword)
                            } label: {
                                Image(systemName: "minus")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(VibePalette.inkFaint)
                                    .frame(width: 30, height: 30)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 12)
                        Hairline()
                    }
                }

                HStack(spacing: 12) {
                    TextField("New keyword", text: $newKeyword)
                        .font(.system(size: 14))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .recessedWell(corner: 12)
                    Button {
                        viewModel.addLeaveKeyword(newKeyword)
                        newKeyword = ""
                    } label: {
                        Text("ADD")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(VibePalette.ink)
                            .frame(width: 78, height: 42)
                            .machinedPlate(corner: 12)
                    }
                    .buttonStyle(KeyPressStyle())
                    .disabled(newKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.top, 18)
            }
            .padding(.horizontal, 26)
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
        .background(VibePalette.paper.ignoresSafeArea())
        .navigationTitle("Leave Keywords")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Add Subscription Sheet

public struct AddSubscriptionSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var urlText: String = ""
    @State private var validationMessage: String?

    public var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Any published .ics feed works, including a shared family calendar.")
                        .font(.system(size: 12))
                        .lineSpacing(3)
                        .foregroundStyle(VibePalette.inkFaint)

                    field("Name", text: $name, prompt: "Calendar name", keyboard: .default)
                    field("Link", text: $urlText, prompt: "https:// or webcal://", keyboard: .URL)

                    if let validationMessage {
                        Text(validationMessage)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.red)
                    }

                    Button {
                        addSubscription()
                    } label: {
                        Text("ADD CALENDAR")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(VibePalette.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .machinedPlate(corner: 16)
                    }
                    .buttonStyle(KeyPressStyle())
                }
                .padding(.horizontal, 26)
                .padding(.top, 18)
                .padding(.bottom, 40)
            }
            .background(VibePalette.paper.ignoresSafeArea())
            .navigationTitle("Add Subscription")
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

    private func field(
        _ title: String,
        text: Binding<String>,
        prompt: String,
        keyboard: UIKeyboardType
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .vibeCaption()
            TextField(prompt, text: text)
                .font(.system(size: 14))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(keyboard)
                .foregroundStyle(VibePalette.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .recessedWell(corner: 12)
        }
    }

    private func addSubscription() {
        let trimmedURL = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmedURL.replacingOccurrences(of: "webcal://", with: "https://")
        guard let url = URL(string: normalized), url.scheme == "https" else {
            validationMessage = "Enter a valid https:// or webcal:// link."
            return
        }
        let finalName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        viewModel.addSubscription(
            name: finalName.isEmpty ? "Calendar Subscription" : finalName,
            url: normalized,
            region: .custom
        )
        dismiss()
    }
}
