import SwiftUI

@main
struct __MODULE_NAME__App: App {
    var body: some Scene {
        Window(AppConfig.displayName) {
            ContentView()
        }

        Settings {
            Text("Settings")
                .padding()
        }
    }
}
