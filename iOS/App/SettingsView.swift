import SwiftUI
import UIKit
import VibeAlarmCore

/// The Sources tab: holiday feeds, the on-device calendar, snooze, and the optional key.
public struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var apiKeyInput: String = ""
    @State private var provider: BYOKProviderKind = .openAICompatible
    @State private var modelName: String = ""
    @State private var endpointURL: String = ""
    @State private var byokStatusMessage: String?
    @State private var showAddCountrySheet = false
    @State private var showAddSubscriptionSheet = false
    @State private var showLeaveKeywords = false
    @State private var showBYOKDetails = false

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(viewModel.snapshot.subscriptions) { sub in
                        subscriptionRow(sub)
                    }

                    Button {
                        showAddCountrySheet = true
                    } label: {
                        labeledChevron(
                            "Add Country",
                            detail: "\(HolidayCatalog.all.count) public holiday feeds, searchable"
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        showAddSubscriptionSheet = true
                    } label: {
                        labeledChevron("Add Custom URL")
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await viewModel.syncExternalSubscriptions() }
                    } label: {
                        LabeledContent(viewModel.isSyncingICS ? "Syncing" : "Refresh All") {
                            Text(lastRefreshDetail)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(viewModel.isSyncingICS)
                } header: {
                    Text("Holiday Calendars")
                }

                Section {
                    LabeledContent("Access") {
                        Text(viewModel.localCalendarManager.accessStatusLabel)
                            .foregroundStyle(.secondary)
                    }

                    if viewModel.localCalendarManager.hasReadAccess {
                        ForEach(viewModel.localCalendarManager.availableCalendars) { cal in
                            Toggle(cal.title, isOn: Binding(
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
                        }
                    } else if viewModel.localCalendarManager.authorizationStatus == .denied
                                || viewModel.localCalendarManager.authorizationStatus == .restricted {
                        Button("Open iOS Settings") { openSystemSettings() }
                    } else {
                        Button("Grant Access") {
                            Task { _ = await viewModel.localCalendarManager.requestAccess() }
                        }
                    }

                    Button {
                        showLeaveKeywords = true
                    } label: {
                        labeledChevron(
                            "Leave Keywords",
                            detail: "\(viewModel.snapshot.leaveKeywords.count) keywords mark personal leave"
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await viewModel.syncLocalCalendars() }
                    } label: {
                        LabeledContent("Scan Now") {
                            Text(lastScanDetail)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("iOS Calendar")
                } footer: {
                    Text("Read-only. Events never leave this iPhone.")
                }

                Section {
                    Picker("Snooze Interval", selection: snoozeSelection) {
                        ForEach(snoozeChoices, id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Used by the notification action and the wake alarm.")
                }

                Section {
                    Toggle("Edit Key", isOn: $showBYOKDetails)

                    if showBYOKDetails {
                        byokDetails
                    }
                } header: {
                    Text("AI Import")
                } footer: {
                    Text(KeychainHelper.loadAPIKey().isEmpty
                         ? "No key stored. Paste notices by hand instead."
                         : "Stored in the iOS Keychain.")
                }

                Section {
                    Text("Everything stays on this iPhone. No account, no server, no analytics.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Sources")
            .onAppear { loadInitialState() }
            .sheet(isPresented: $showAddCountrySheet) {
                HolidayCatalogSearchSheet(viewModel: viewModel)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showAddSubscriptionSheet) {
                AddSubscriptionSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $showLeaveKeywords) {
                NavigationStack { LeaveKeywordsEditorView(viewModel: viewModel) }
            }
        }
    }

    // MARK: - Holiday Calendars

    private func subscriptionRow(_ sub: ExternalCalendarSubscription) -> some View {
        Toggle(isOn: Binding(
            get: { sub.isEnabled },
            set: { viewModel.toggleSubscription(id: sub.id, isEnabled: $0) }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sub.name)
                    .foregroundStyle(sub.isEnabled ? Color.primary : Color.secondary)
                Text(URL(string: sub.url)?.host ?? sub.url)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                viewModel.removeSubscription(id: sub.id)
            } label: {
                Label("Remove Calendar", systemImage: "trash")
            }
        }
        .swipeActions {
            Button(role: .destructive) {
                viewModel.removeSubscription(id: sub.id)
            } label: {
                Label("Remove Calendar", systemImage: "trash")
            }
        }
    }

    private var lastRefreshDetail: String {
        guard let latest = viewModel.snapshot.subscriptions.compactMap(\.lastSyncedAt).max() else {
            return "Never synced"
        }
        return "Last synced \(Self.timeFormatter.string(from: latest))"
    }

    private var lastScanDetail: String {
        guard let lastScan = viewModel.lastLocalCalendarScanAt else { return "Not scanned yet" }
        return "Last scanned \(Self.timeFormatter.string(from: lastScan))"
    }

    // MARK: - Snooze

    private var snoozeChoices: [Int] {
        var options = AlarmRule.snoozeIntervalOptions
        if !options.contains(viewModel.snoozeMinutes) {
            options.append(viewModel.snoozeMinutes)
            options.sort()
        }
        return options
    }

    private var snoozeSelection: Binding<Int> {
        Binding(
            get: { viewModel.snoozeMinutes },
            set: { viewModel.setSnoozeMinutes($0) }
        )
    }

    // MARK: - AI Import

    @ViewBuilder
    private var byokDetails: some View {
        Picker("Provider", selection: $provider) {
            Text("OpenAI Compatible").tag(BYOKProviderKind.openAICompatible)
            Text("Anthropic").tag(BYOKProviderKind.anthropic)
        }
        .onChange(of: provider) { _, newValue in
            endpointURL = newValue.defaultEndpoint
            modelName = newValue.defaultModel
            persistBYOKConfig()
        }

        LabeledContent("Base URL") {
            TextField("https://", text: $endpointURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .multilineTextAlignment(.trailing)
                .onSubmit { persistBYOKConfig() }
        }

        LabeledContent("Model") {
            TextField("Model", text: $modelName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
                .onSubmit { persistBYOKConfig() }
        }

        LabeledContent("API Key") {
            SecureField("Required", text: $apiKeyInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
                .onSubmit { persistBYOKConfig() }
        }

        Button(viewModel.isTestingBYOKConnection ? "Testing" : "Test Connection") {
            Task {
                saveAPIKey()
                byokStatusMessage = await viewModel.testBYOKConnection()
            }
        }
        .disabled(viewModel.isTestingBYOKConnection)

        Button("Save Key") {
            saveAPIKey()
            byokStatusMessage = "Key saved to the Keychain."
        }

        if let byokStatusMessage {
            Text(byokStatusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func labeledChevron(_ title: String, detail: String? = nil) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
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
        List {
            Section {
                Text("Events in your own calendars whose title or notes contain one of these words are treated as personal leave.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(viewModel.snapshot.leaveKeywords, id: \.self) { keyword in
                    HStack {
                        Text(keyword)
                        Spacer()
                        Button {
                            viewModel.removeLeaveKeyword(keyword)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(keyword)")
                    }
                }
            }

            Section {
                HStack {
                    TextField("New keyword", text: $newKeyword)
                        .textInputAutocapitalization(.never)
                        .onSubmit(addKeyword)
                    Button("Add", action: addKeyword)
                        .disabled(newKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .navigationTitle("Leave Keywords")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
            }
        }
    }

    private func addKeyword() {
        viewModel.addLeaveKeyword(newKeyword)
        newKeyword = ""
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
                    Text("Any published .ics feed works, including a shared family calendar.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextField("Calendar name", text: $name)
                    TextField("https:// or webcal://", text: $urlText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }

                if let validationMessage {
                    Section {
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
