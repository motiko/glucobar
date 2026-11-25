import SwiftUI

@main
struct GlucoBarApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            DropdownView(model: model)
        } label: {
            if model.latest == nil {
                Image(nsImage: MenuBarLabel.gauge).accessibilityLabel("GlucoBar: no Reading")
            } else {
                MenuBarLabel(text: model.menuBarText, color: model.menuBarColor)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}
