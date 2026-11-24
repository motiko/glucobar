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
        .frame(width: 480, height: 380)
        .onChange(of: model.config) { model.saveConfig() }
        // Back to menu-bar-only (no Dock icon) once Settings closes.
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }
}

private struct AccountTab: View {
    @Bindable var model: AppModel
    @State private var email = ""
    @State private var password = ""
    @State private var patients: [LLUPatient] = []

    var body: some View {
        Form {
            Section("LibreLinkUp Follower account") {
                TextField("Email", text: $email)
                SecureField("Password", text: $password)
                Button("Sign in") {
                    model.signIn(email: email, password: password)
                    password = ""
                    Task { patients = await model.loadPatients() }
                }
                .disabled(email.isEmpty || password.isEmpty)
            }
            if patients.count > 1 {
                Section("Patient") {
                    Picker("Show glucose of", selection: $model.config.libreLinkUp.patientId) {
                        ForEach(patients) { Text($0.name).tag(String?.some($0.id)) }
                    }
                    .onChange(of: model.config.libreLinkUp.patientId) { model.restartPolling() }
                }
            }
            Section {
                Text("The password is stored in your Keychain, never in the config file.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { email = model.config.libreLinkUp.email ?? "" }
        .task { patients = await model.loadPatients() }
    }
}

private struct DisplayTab: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Menu bar") {
                Toggle("Show trend arrow", isOn: $model.config.display.showTrend)
                Toggle("Show delta (5 min)", isOn: $model.config.display.showDelta)
                Toggle("Show age", isOn: $model.config.display.showAge)
                Picker("Unit", selection: $model.config.display.unit) {
                    Text("Follow Patient").tag(GlucoseUnit?.none)
                    ForEach(GlucoseUnit.allCases, id: \.self) { Text($0.rawValue).tag(GlucoseUnit?.some($0)) }
                }
                Stepper("Stale after \(model.config.display.staleAfterMinutes) min",
                        value: $model.config.display.staleAfterMinutes, in: 5...60)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AlertsTab: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Thresholds (mg/dL)") {
                thresholdField("Urgent Low", \.urgentLow)
                thresholdField("Low", \.low)
                thresholdField("High", \.high)
            }
            Section("Alerts") {
                ForEach(AlertKind.allCases, id: \.self) { kind in
                    if let settings = Binding($model.config.alerts[kind]) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Toggle(kind.displayName, isOn: settings.enabled)
                                Spacer()
                                Stepper("every \(settings.wrappedValue.repeatMinutes) min",
                                        value: settings.repeatMinutes, in: 1...120)
                            }
                            if let gate = Self.gateLabel(kind) {
                                Toggle(gate, isOn: settings.onlyWithFastTrend)
                                    .font(.callout)
                                    .padding(.leading, 20)
                                    .disabled(!settings.wrappedValue.enabled)
                            }
                        }
                    }
                }
                // TODO: edit each Alert's Action list; Webhook/Telegram Action editors;
                // Telegram chat-id discovery via getUpdates.
                Text("Action lists are edited in the config file for now.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    static func gateLabel(_ kind: AlertKind) -> String? {
        switch kind {
        case .low: "Only while falling fast ↓"
        case .high: "Only while rising fast ↑"
        default: nil
        }
    }

    private func thresholdField(_ title: String, _ path: WritableKeyPath<Thresholds, Glucose>) -> some View {
        TextField(title, value: Binding(
            get: { Int(model.config.thresholds[keyPath: path].mgPerDL.rounded()) },
            set: { model.config.thresholds[keyPath: path] = Glucose(mgPerDL: Double($0)) }
        ), format: .number)
    }
}

private struct GeneralTab: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $model.config.launchAtLogin)
                .onChange(of: model.config.launchAtLogin) { _, on in LaunchAtLogin.apply(on) }
            Stepper("Poll every \(model.config.polling.intervalSeconds) s",
                    value: $model.config.polling.intervalSeconds,
                    in: PollingConfig.minimumIntervalSeconds...600, step: 30)
            HStack {
                Button("Show config file") {
                    NSWorkspace.shared.activateFileViewerSelecting([model.configStore.url])
                }
                Button("Reload config file") { model.reloadConfig() }
            }
        }
        .formStyle(.grouped)
    }
}
