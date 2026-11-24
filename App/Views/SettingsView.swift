import AppKit
import GlucoBarCore
import SwiftUI

/// Edits the same JSON config file a user can edit by hand (docs/adr/0002).
struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            AccountTab(model: model).tabItem { Label("Account", systemImage: "person.crop.circle") }
            DisplayTab(model: model).tabItem { Label("Display", systemImage: "menubar.rectangle") }
            AlertsTab(model: model).tabItem { Label("Alerts", systemImage: "bell") }
            GeneralTab(model: model).tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 500, height: 520)
        .onChange(of: model.config) { model.saveConfig() }
        // Back to menu-bar-only (no Dock icon) once Settings closes.
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }
}

// MARK: - Account

private struct AccountTab: View {
    @Bindable var model: AppModel
    @State private var email = ""
    @State private var password = ""
    @State private var editing = false
    @State private var patients: [LLUPatient] = []

    var body: some View {
        Form {
            Section {
                ConnectionStatusRow(model: model)
            }

            if model.hasCredentials && !editing {
                Section("LibreLinkUp account") {
                    LabeledContent("Signed in as", value: model.config.libreLinkUp.email ?? "")
                    HStack {
                        Spacer()
                        Button("Change Account…") {
                            email = model.config.libreLinkUp.email ?? ""
                            editing = true
                        }
                        Button("Sign Out", role: .destructive) { model.signOut() }
                    }
                }
            } else {
                Section {
                    TextField("Email", text: $email, prompt: Text("name@example.com"))
                        .textContentType(.username)
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .onSubmit(signIn)
                    HStack {
                        Spacer()
                        if editing { Button("Cancel") { editing = false; password = "" } }
                        Button("Sign In", action: signIn)
                            .keyboardShortcut(.defaultAction)
                            .buttonStyle(.borderedProminent)
                            .disabled(email.isEmpty || password.isEmpty)
                    }
                } header: {
                    Text("Sign in to LibreLinkUp")
                } footer: {
                    Text("Use the LibreLinkUp (follower) account that your Libre app shares its data with. "
                         + "The password is stored in your Keychain, never in the config file.")
                }
            }

            if patients.count > 1 {
                Section {
                    Picker("Show glucose of", selection: $model.config.libreLinkUp.patientId) {
                        ForEach(patients) { Text($0.name).tag(String?.some($0.id)) }
                    }
                    .onChange(of: model.config.libreLinkUp.patientId) { model.restartPolling() }
                } header: {
                    Text("Patient")
                } footer: {
                    Text("This account follows several people. GlucoBar shows one of them.")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { email = model.config.libreLinkUp.email ?? "" }
        .task(id: model.hasCredentials) { patients = model.hasCredentials ? await model.loadPatients() : [] }
    }

    private func signIn() {
        guard !email.isEmpty, !password.isEmpty else { return }
        model.signIn(email: email, password: password)
        password = ""
        editing = false
    }
}

/// "● Connected · last reading 08:12 (2 min ago)", or what's wrong.
private struct ConnectionStatusRow: View {
    let model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            LabeledContent("Status") {
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 6) {
                        Circle().fill(color).frame(width: 8, height: 8)
                        Text(title).foregroundStyle(.primary)
                    }
                    if let detail = detail(now: context.date) {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
    }

    private var color: Color {
        switch model.status {
        case .ok: model.isStale() ? .orange : .green
        case .starting: .yellow
        case .notSignedIn: .gray
        case .error: .red
        }
    }

    private var title: String {
        switch model.status {
        case .ok: model.isStale() ? "Connected, no recent reading" : "Connected"
        case .starting: "Connecting…"
        case .notSignedIn: "Not signed in"
        case .error: "Problem"
        }
    }

    private func detail(now: Date) -> String? {
        switch model.status {
        case .error(let message): return message
        case .notSignedIn: return "Sign in below to see your glucose."
        case .starting: return nil
        case .ok:
            guard let r = model.latest else { return "No readings yet" }
            let minutes = max(0, Int(now.timeIntervalSince(r.timestamp) / 60))
            let ago = minutes == 0 ? "just now" : "\(minutes) min ago"
            return "Last reading \(r.timestamp.formatted(date: .omitted, time: .shortened)) (\(ago))"
        }
    }
}

// MARK: - Display

private struct DisplayTab: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Menu bar shows") {
                Toggle("Trend arrow", isOn: $model.config.display.showTrend)
                Toggle("Change over 5 min (delta)", isOn: $model.config.display.showDelta)
                Toggle("Age of reading", isOn: $model.config.display.showAge)
            }
            Section {
                Picker("Unit", selection: $model.config.display.unit) {
                    Text("Same as Libre app").tag(GlucoseUnit?.none)
                    ForEach(GlucoseUnit.allCases, id: \.self) { Text($0.rawValue).tag(GlucoseUnit?.some($0)) }
                }
            }
            Section {
                MinutesPicker(title: "Grey out reading after", minutes: $model.config.display.staleAfterMinutes,
                              choices: [5, 10, 15, 20, 30, 45, 60])
            } header: {
                Text("No new readings")
            } footer: {
                Text("If no new reading arrives for this long, the value in the menu bar turns grey "
                     + "and the Signal Loss alert fires.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Alerts

private struct AlertsTab: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            ForEach([AlertKind.urgentLow, .low, .high, .signalLoss], id: \.self) { kind in
                if let settings = Binding($model.config.alerts[kind]) {
                    AlertSection(model: model, kind: kind, settings: settings)
                }
            }
            Section {
                // TODO: edit each Alert's Action list; Webhook/Telegram Action editors;
                // Telegram chat-id discovery via getUpdates.
                LabeledContent("Sounds and messages") {
                    Button("Edit in Config File…") {
                        NSWorkspace.shared.activateFileViewerSelecting([model.configStore.url])
                    }
                }
            } footer: {
                Text("Which sound or message each alert triggers is set in the config file for now.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct AlertSection: View {
    @Bindable var model: AppModel
    let kind: AlertKind
    @Binding var settings: AlertSettings

    var body: some View {
        Section {
            Toggle("Alert me", isOn: $settings.enabled)
            Group {
                switch kind {
                case .urgentLow: GlucoseField(title: "When below", model: model, path: \.urgentLow)
                case .low: GlucoseField(title: "When below", model: model, path: \.low)
                case .high: GlucoseField(title: "When above", model: model, path: \.high)
                case .signalLoss:
                    MinutesPicker(title: "When no reading for", minutes: $model.config.display.staleAfterMinutes,
                                  choices: [5, 10, 15, 20, 30, 45, 60])
                }
                if let gate {
                    Toggle(isOn: $settings.onlyWithFastTrend) {
                        Text(gate.title)
                        Text(gate.explanation)
                    }
                }
                MinutesPicker(title: "Repeat every", minutes: $settings.repeatMinutes,
                              choices: [1, 5, 10, 15, 20, 30, 45, 60, 90, 120])
            }
            .disabled(!settings.enabled)
        } header: {
            Text(kind.displayName)
        }
    }

    private var gate: (title: String, explanation: String)? {
        switch kind {
        case .low: ("Only while falling fast ↓", "Stays quiet while glucose just hovers below the limit.")
        case .high: ("Only while rising fast ↑", "Stays quiet while glucose just hovers above the limit.")
        default: nil
        }
    }
}

/// A glucose threshold, edited in the display unit and stored in mg/dL.
private struct GlucoseField: View {
    let title: String
    @Bindable var model: AppModel
    let path: WritableKeyPath<Thresholds, Glucose>

    var body: some View {
        let unit = model.unit
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(title, value: Binding(
                    get: { (model.config.thresholds[keyPath: path].value(in: unit) * 10).rounded() / 10 },
                    set: { model.config.thresholds[keyPath: path] = unit == .mgPerDL
                        ? Glucose(mgPerDL: $0) : Glucose(mmolPerL: $0) }
                ), format: .number.precision(.fractionLength(unit == .mgPerDL ? 0 : 1)))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
                Text(unit.rawValue).foregroundStyle(.secondary)
            }
        }
    }
}

/// A menu of minute values; keeps a custom value from the config file selectable.
private struct MinutesPicker: View {
    let title: String
    @Binding var minutes: Int
    let choices: [Int]

    var body: some View {
        Picker(title, selection: $minutes) {
            ForEach(Array(Set(choices + [minutes])).sorted(), id: \.self) { m in
                Text(Self.label(m)).tag(m)
            }
        }
    }

    static func label(_ m: Int) -> String {
        switch m {
        case 60: "1 hour"
        case 120: "2 hours"
        case _ where m > 60 && m % 60 == 0: "\(m / 60) hours"
        case 1: "1 minute"
        default: "\(m) minutes"
        }
    }
}

// MARK: - General

private struct GeneralTab: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $model.config.launchAtLogin)
                    .onChange(of: model.config.launchAtLogin) { _, on in LaunchAtLogin.apply(on) }
                Picker("Check for new readings every", selection: $model.config.polling.intervalSeconds) {
                    ForEach(Array(Set([60, 120, 300, model.config.polling.intervalSeconds])).sorted(), id: \.self) { s in
                        Text(s < 120 ? "\(s) seconds" : "\(s / 60) minutes").tag(s)
                    }
                }
            }
            Section {
                LabeledContent("Config file") {
                    HStack {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([model.configStore.url])
                        }
                        Button("Reload") { model.reloadConfig() }
                    }
                }
            } footer: {
                Text(model.configStore.url.path(percentEncoded: false))
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
    }
}
