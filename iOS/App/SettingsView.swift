import SwiftUI
import UIKit
import VibeAlarmCore

/// The Sources tab: iOS Calendar access, calendar subscriptions, the on-device
/// AI parser (BYOK), and a one-line privacy statement. Native `Form` sections only.
public struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var apiKeyInput: String = ""
    @State private var provider: BYOKProviderKind = .openAICompatible
    @State private var modelName: String = ""
    @State private var endpointURL: String = ""
    @State private var byokStatusMessage: String?
    @State private var showAddCountrySheet = false
    @State private var showAddSubscriptionSheet = false
    @State private var showSnoozeDial = false

    private let snoozeOptions: [String] = AlarmRule.snoozeIntervalOptions.map { "\($0) min" }

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            Form {
                holidayCalendarsSection
                iOSCalendarSection
                snoozeSection
                byokSection
                privacySection
            }
            .scrollContentBackground(.hidden)
            .background(calmBackground)
            // Keep the last rows clear of the floating tab bar.
            .contentMargins(.bottom, 96, for: .scrollContent)
            .navigationTitle("Sources")
            .onAppear {
                loadInitialState()
            }
            .sheet(isPresented: $showAddCountrySheet) {
                HolidayCatalogSearchSheet(viewModel: viewModel)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showAddSubscriptionSheet) {
                AddSubscriptionSheet(viewModel: viewModel)
            }
        }
        .tint(.vibeAccent)
    }

    // MARK: - Calm Background

    /// A soft, full-bleed light background with a very subtle accent wash, matching the Wake
    /// Time editor. No images, no heavy gradients.
    private var calmBackground: some View {
        LinearGradient(
            colors: [
                Color(.systemGroupedBackground),
                Color.vibeAccent.opacity(0.04),
                Color(.systemGroupedBackground)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Row Icon Badge

    /// An iOS Settings-style tinted rounded-square glyph used as a row leading accessory.
    private func iconBadge(_ systemName: String, _ color: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color)
            )
    }

    // MARK: - 2. iOS Calendar

    private var iOSCalendarSection: some View {
        Section {
            HStack {
                Text("Access")
                Spacer()
                Text(viewModel.localCalendarManager.accessStatusLabel)
                    .foregroundStyle(.secondary)
            }

            if viewModel.localCalendarManager.hasReadAccess {
                ForEach(viewModel.localCalendarManager.availableCalendars) { cal in
                    calendarToggleRow(cal)
                }
            } else if viewModel.localCalendarManager.authorizationStatus == .denied
                        || viewModel.localCalendarManager.authorizationStatus == .restricted {
                Button("Open Settings") {
                    openSystemSettings()
                }
            } else {
                Button("Grant Access") {
                    Task { _ = await viewModel.localCalendarManager.requestAccess() }
                }
            }

            NavigationLink("Leave Keywords") {
                LeaveKeywordsEditorView(viewModel: viewModel)
            }

            Button {
                Task { await viewModel.syncLocalCalendars() }
            } label: {
                HStack {
                    Text("Scan Now")
                        .foregroundStyle(.primary)
                    Spacer()
                    if let lastScan = viewModel.lastLocalCalendarScanAt {
                        Text(Self.timeFormatter.string(from: lastScan))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("iOS Calendar")
        } footer: {
            Text("Read-only. Calendar data never leaves this device.")
        }
    }

    private func calendarToggleRow(_ cal: LocalCalendarSourceInfo) -> some View {
        Toggle(isOn: Binding(
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
        )) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: cal.colorHex))
                    .frame(width: 8, height: 8)
                Text(cal.title)
            }
        }
    }

    // MARK: - 1. Holiday Calendars

    private var holidayCalendarsSection: some View {
        Section {
            ForEach(viewModel.snapshot.subscriptions) { sub in
                subscriptionRow(sub)
            }

            Button {
                showAddCountrySheet = true
            } label: {
                HStack(spacing: 12) {
                    iconBadge("globe", .green)
                    Text("Add Country")
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }

            Button("Add Custom URL…") {
                showAddSubscriptionSheet = true
            }

            Button {
                Task { await viewModel.syncExternalSubscriptions() }
            } label: {
                Text(viewModel.isSyncingICS ? "Refreshing…" : "Refresh All")
            }
            .disabled(viewModel.isSyncingICS)
        } header: {
            Text("Holiday Calendars")
        } footer: {
            if let latest = viewModel.snapshot.subscriptions.compactMap(\.lastSyncedAt).max() {
                Text("Last refreshed \(Self.timeFormatter.string(from: latest))")
            }
        }
    }

    private func subscriptionRow(_ sub: ExternalCalendarSubscription) -> some View {
        Toggle(isOn: Binding(
            get: { sub.isEnabled },
            set: { enabled in viewModel.toggleSubscription(id: sub.id, isEnabled: enabled) }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sub.name)
                Text(URL(string: sub.url)?.host ?? sub.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .swipeActions {
            Button(role: .destructive) {
                viewModel.removeSubscription(id: sub.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - 3. Snooze

    private var snoozeSection: some View {
        Section {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSnoozeDial.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    iconBadge("zzz", .indigo)
                    Text("Snooze Interval")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(viewModel.snoozeMinutes) min")
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showSnoozeDial ? 90 : 0))
                }
            }

            if showSnoozeDial {
                RotaryOptionDial(
                    options: snoozeOptions,
                    selectedIndex: snoozeIndex,
                    accessibilityLabelText: "Snooze Interval"
                ) { idx in
                    selectSnoozeIndex(idx)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
        } header: {
            Text("Snooze")
        } footer: {
            Text("Used by the notification snooze action and the wake alarm.")
        }
    }

    private var snoozeIndex: Int {
        AlarmRule.snoozeIntervalOptions.firstIndex(of: viewModel.snoozeMinutes) ?? 0
    }

    private func selectSnoozeIndex(_ idx: Int) {
        guard AlarmRule.snoozeIntervalOptions.indices.contains(idx) else { return }
        viewModel.setSnoozeMinutes(AlarmRule.snoozeIntervalOptions[idx])
    }

    // MARK: - 4. AI Import (BYOK)

    private var byokSection: some View {
        Section {
            Picker("Provider", selection: $provider) {
                Text("OpenAI Compatible").tag(BYOKProviderKind.openAICompatible)
                Text("Anthropic").tag(BYOKProviderKind.anthropic)
            }
            .onChange(of: provider) { _, newValue in
                endpointURL = newValue.defaultEndpoint
                modelName = newValue.defaultModel
                persistBYOKConfig()
            }

            HStack {
                Text("Base URL")
                Spacer()
                TextField("URL", text: $endpointURL)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(.secondary)
                    .onSubmit { persistBYOKConfig() }
            }

            HStack {
                Text("Model")
                Spacer()
                TextField("Model", text: $modelName)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(.secondary)
                    .onSubmit { persistBYOKConfig() }
            }

            HStack {
                Text("API Key")
                Spacer()
                SecureField("Required", text: $apiKeyInput)
                    .multilineTextAlignment(.trailing)
                    .onSubmit { saveAPIKey() }
            }

            Button("Test Connection") {
                Task {
                    saveAPIKey()
                    byokStatusMessage = await viewModel.testBYOKConnection()
                }
            }
            .disabled(viewModel.isTestingBYOKConnection)
        } header: {
            Text("AI Import (BYOK)")
        } footer: {
            Text(byokStatusMessage ?? "Stored on this device in the Keychain.")
        }
    }

    // MARK: - 5. Privacy

    private var privacySection: some View {
        Section {
            Text("Everything stays on this iPhone. No account, no server.")
                .font(.footnote)
                .foregroundStyle(.secondary)
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
        viewModel.localCalendarManager.refreshAuthorizationStatus()
    }

    private func persistBYOKConfig() {
        viewModel.updateBYOKConfig(
            BYOKConfiguration(provider: provider, endpointURL: endpointURL, model: modelName)
        )
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - Leave Keywords Editor (Pushed)

public struct LeaveKeywordsEditorView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var newKeyword: String = ""

    public var body: some View {
        List {
            Section {
                ForEach(viewModel.snapshot.leaveKeywords, id: \.self) { keyword in
                    Text(keyword)
                }
                .onDelete { offsets in
                    for index in offsets {
                        viewModel.removeLeaveKeyword(viewModel.snapshot.leaveKeywords[index])
                    }
                }
            } footer: {
                Text("Local calendar events whose title or notes contain one of these words are treated as personal leave.")
            }

            Section {
                HStack {
                    TextField("New keyword", text: $newKeyword)
                    Button("Add") {
                        viewModel.addLeaveKeyword(newKeyword)
                        newKeyword = ""
                    }
                    .disabled(newKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
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
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("https:// or webcal:// link", text: $urlText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } footer: {
                    if let validationMessage {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addSubscription() }
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(.vibeAccent)
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

// MARK: - Hex Color Helper

private extension Color {
    init(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized.removeAll { $0 == "#" }
        var value: UInt64 = 0
        _ = Scanner(string: sanitized).scanHexInt64(&value)
        let r = Double((value & 0xFF0000) >> 16) / 255.0
        let g = Double((value & 0x00FF00) >> 8) / 255.0
        let b = Double(value & 0x0000FF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }
}
