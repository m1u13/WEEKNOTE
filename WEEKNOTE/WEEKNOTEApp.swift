import SwiftUI

@main
struct WEEKNOTEApp: App {
    @StateObject private var store: PlannerStore
    @AppStorage("appearance") private var appearance = "system"

    init() {
        let testing = ProcessInfo.processInfo.arguments.contains("--uitesting")
        if testing {
            UserDefaults.standard.set("system", forKey: "appearance")
            HabitTimer.shared.reset()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("weeknote-ui-tests.json")
            let value = PlannerStore(fileURL: url)
            value.reset(includeSamples: true)
            _store = StateObject(wrappedValue: value)
        } else {
            _store = StateObject(wrappedValue: PlannerStore())
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environment(\.locale, Locale(identifier: "ja_JP"))
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
        }
    }
}
