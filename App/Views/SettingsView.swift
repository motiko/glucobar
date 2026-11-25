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
            ActionsTab(model: model).tabItem { Label("Actions", systemImage: "paperplane") }
            GeneralTab(model: model).tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 520, height: 560)
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
                LabeledContent("Then") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.config.actions.keys.sorted(), id: \.self) { name in
                            Toggle(model.config.actions[name]?.label(name: name) ?? name, isOn: uses(name))
                                .toggleStyle(.checkbox)
                        }
                    }
                }
            }
            .disabled(!settings.enabled)
            TestSendRow(title: "Send test \(kind.displayName)", disabled: settings.actions.isEmpty) {
                await model.sendTest(kind)
            }
        } header: {
            Text(kind.displayName)
        } footer: {
            if kind == .signalLoss {
                Text("Add phone push (ntfy) or a webhook in the Actions tab.")
            }
        }
    }

    private func uses(_ name: String) -> Binding<Bool> {
        Binding(
            get: { settings.actions.contains(name) },
            set: { on in
                settings.actions.removeAll { $0 == name }
                if on { settings.actions.append(name) }
            })
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

/// A "Send test" button that shows, per Action, whether it went out.
private struct TestSendRow: View {
    let title: String
    var disabled = false
    let send: () async -> [(action: String, error: String?)]
    @State private var sending = false
    @State private var results: [(action: String, error: String?)]?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let results, !sending {
                    let failed = results.filter { $0.error != nil }.count
                    Label(failed == 0 ? "Sent" : "\(failed) of \(results.count) failed",
                          systemImage: failed == 0 ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(failed == 0 ? .green : .red)
                        .font(.callout)
                }
                Spacer()
                if sending { ProgressView().controlSize(.small) }
                Button(title) {
                    sending = true
                    Task {
                        results = await send()
                        sending = false
                    }
                }
                .disabled(disabled || sending)
            }
            ForEach(results?.filter { $0.error != nil } ?? [], id: \.action) { r in
                Text("\(r.action): \(r.error ?? "")").font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
        }
    }
}

// MARK: - Actions

extension ActionConfig {
    /// How an Action is shown in Settings, e.g. "Phone push (ntfy: glucobar-x7…)".
    func label(name: String) -> String {
        switch self {
        case .sound(let c): c.sound == .urgent ? "Play Urgent sound" : "Play Notification sound"
        case .ntfy(let c): "Phone push (ntfy: \(c.topic.isEmpty ? "no topic" : c.topic))"
        case .webhook(let c): "Webhook (\(URL(string: c.url)?.host() ?? "no URL"))"
        case .telegram: "Telegram \(name) (not supported yet)"
        }
    }
}

private struct ActionsTab: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            ForEach(model.config.actions.keys.sorted(), id: \.self) { name in
                ActionSection(model: model, name: name)
            }
            Section {
                HStack {
                    Spacer()
                    Menu("Add Action") {
                        Button("Phone push (ntfy)") {
                            add("phone", .ntfy(NtfyActionConfig(topic: Self.randomTopic())))
                        }
                        Button("Webhook") { add("webhook", .webhook(WebhookActionConfig(url: ""))) }
                    }
                    .fixedSize()
                }
            } footer: {
                Text("Choose which Actions each alert uses in the Alerts tab.")
            }
        }
        .formStyle(.grouped)
    }

    private func add(_ base: String, _ action: ActionConfig) {
        var name = base
        var n = 2
        while model.config.actions[name] != nil { name = "\(base)\(n)"; n += 1 }
        model.config.actions[name] = action
    }

    static func randomTopic() -> String {
        let chars = Array("abcdefghijkmnpqrstuvwxyz23456789")
        return "glucobar-" + String((0..<16).map { _ in chars.randomElement()! })
    }
}

private struct ActionSection: View {
    @Bindable var model: AppModel
    let name: String

    var body: some View {
        Section {
            switch model.config.actions[name] {
            case .sound(let c):
                Toggle(isOn: Binding(
                    get: { c.bypassFocusAndMute },
                    set: { var v = c; v.bypassFocusAndMute = $0; model.config.actions[name] = .sound(v) })) {
                    Text("Play even during Focus")
                    Text("Plays the sound directly, so Do Not Disturb can't silence it.")
                }
            case .ntfy(let c):
                ntfyFields(c)
            case .webhook(let c):
                webhookFields(c)
            case .telegram:
                Text("Telegram isn't supported yet.").foregroundStyle(.secondary)
            case nil:
                EmptyView()
            }
            HStack {
                if case .sound = model.config.actions[name] {} else {
                    Button("Delete", role: .destructive, action: delete)
                }
                TestSendRow(title: "Send test") {
                    [(name, await model.sendTest(action: name))]
                }
            }
        } header: {
            Text(model.config.actions[name]?.label(name: name) ?? name)
        }
    }

    @ViewBuilder private func ntfyFields(_ c: NtfyActionConfig) -> some View {
        let set: (NtfyActionConfig) -> Void = { model.config.actions[name] = .ntfy($0) }
        TextField("Topic", text: Binding(get: { c.topic }, set: { var v = c; v.topic = $0.trimmingCharacters(in: .whitespaces); set(v) }))
        TextField("Server", text: Binding(get: { c.server }, set: { var v = c; v.server = $0; set(v) }))
        SecretRow(model: model, title: "Access token", prompt: "optional, tk_…",
                  secretName: Binding(get: { c.tokenSecret }, set: { var v = c; v.tokenSecret = $0; set(v) }),
                  defaultName: "ntfy.\(name).token")
        if c.server == NtfyActionConfig.defaultServer, !c.topic.isEmpty {
            Text("Subscribe to **\(c.topic)** in the ntfy app. Anyone who knows the topic name can read these alerts, so keep it random.")
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }

    @ViewBuilder private func webhookFields(_ c: WebhookActionConfig) -> some View {
        let set: (WebhookActionConfig) -> Void = { model.config.actions[name] = .webhook($0) }
        TextField("URL", text: Binding(get: { c.url }, set: { var v = c; v.url = $0.trimmingCharacters(in: .whitespaces); set(v) }),
                  prompt: Text("https://example.com/hook"))
        SecretRow(model: model, title: "Authorization header", prompt: "optional, e.g. Bearer …",
                  secretName: Binding(get: { c.authorizationSecret }, set: { var v = c; v.authorizationSecret = $0; set(v) }),
                  defaultName: "webhook.\(name).authorization")
        Text("POSTs JSON: alert, state, value, value_mgdl, unit, trend, delta, timestamp.")
            .font(.caption).foregroundStyle(.secondary)
    }

    private func delete() {
        switch model.config.actions[name] {
        case .ntfy(let c): c.tokenSecret.map { model.setSecret(nil, named: $0) }
        case .webhook(let c): c.authorizationSecret.map { model.setSecret(nil, named: $0) }
        default: break
        }
        for kind in model.config.alerts.keys { model.config.alerts[kind]?.actions.removeAll { $0 == name } }
        model.config.actions[name] = nil
    }
}

/// A secret kept in the Keychain; the config only stores its name.
private struct SecretRow: View {
    @Bindable var model: AppModel
    let title: String
    let prompt: String
    @Binding var secretName: String?
    let defaultName: String
    @State private var value = ""
    @State private var stored = false

    var body: some View {
        LabeledContent(title) {
            if stored {
                HStack {
                    Text("Saved in Keychain").foregroundStyle(.secondary)
                    Button("Remove") {
                        if let secretName { model.setSecret(nil, named: secretName) }
                        secretName = nil
                        stored = false
                    }
                }
            } else {
                HStack {
                    SecureField(title, text: $value, prompt: Text(prompt))
                        .labelsHidden()
                        .onSubmit(save)
                    Button("Save", action: save).disabled(value.isEmpty)
                }
            }
        }
        .onAppear { stored = secretName.map(model.hasSecret) ?? false }
    }

    private func save() {
        guard !value.isEmpty else { return }
        let name = secretName ?? defaultName
        model.setSecret(value, named: name)
        secretName = name
        value = ""
        stored = model.hasSecret(name)
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
                Toggle("Debug logging", isOn: $model.config.debugLogging)
            } footer: {
                Text("Writes glucose values to the macOS system log in clear text. Off: they're redacted (“<private>”).")
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
