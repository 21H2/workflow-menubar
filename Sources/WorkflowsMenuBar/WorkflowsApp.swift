import SwiftUI

@main
struct WorkflowsMenuBarApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(state)
                .onAppear { state.bootstrap() }
        } label: {
            MenuBarLabel(state: state)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The icon + count shown in the menu bar — glanceable state without opening the app.
struct MenuBarLabel: View {
    @ObservedObject var state: AppState

    var body: some View {
        if state.runningCount > 0 {
            // Something is running → spinning-feel gear + live count.
            Label("\(state.runningCount)", systemImage: "gearshape.2.fill")
                .labelStyle(.titleAndIcon)
        } else if state.unseenFailures > 0 {
            // Idle but a recent run failed → attention indicator + count.
            Label("\(state.unseenFailures)", systemImage: "exclamationmark.triangle.fill")
                .labelStyle(.titleAndIcon)
        } else if case .signedIn = state.phase {
            // Signed in, all clear.
            Image(systemName: "checkmark.seal")
        } else {
            Image(systemName: "gearshape.2")
        }
    }
}
