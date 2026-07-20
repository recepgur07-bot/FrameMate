import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppConfig.displayName)
                .font(.largeTitle.bold())

            Text("Your Codex-ready macOS starter is running.")
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 480, minHeight: 280, alignment: .topLeading)
        .padding(24)
    }
}

#Preview {
    ContentView()
}
