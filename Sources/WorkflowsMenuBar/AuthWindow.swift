import AppKit
import SwiftUI

/// A floating, always-on-top window that shows the device-flow code so it stays
/// visible even after the menu-bar popover closes or the browser takes focus.
@MainActor
final class AuthWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private weak var state: AppState?

    func show(state: AppState) {
        self.state = state
        if window == nil {
            let root = AuthWindowView().environmentObject(state)
            let hosting = NSHostingController(rootView: root)
            let w = NSWindow(contentViewController: hosting)
            w.title = "Sign in to GitHub"
            w.styleMask = [.titled, .closable]
            w.level = .floating
            w.isReleasedWhenClosed = false
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.setContentSize(NSSize(width: 380, height: 360))
            w.center()
            w.delegate = self
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard let window else { return }
        window.delegate = nil          // avoid windowWillClose -> cancel feedback loop
        window.close()
        self.window = nil
    }

    // User clicked the red close button -> treat as cancel.
    func windowWillClose(_ notification: Notification) {
        window = nil
        if let state, case .awaitingAuth = state.phase {
            state.cancelAuth()
        }
    }
}

struct AuthWindowView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "gearshape.2.fill")
                .font(.system(size: 34))
                .foregroundStyle(.tint)

            Text("Authorize on GitHub").font(.title3.bold())

            if case .awaitingAuth(let code, let uri) = state.phase {
                Text("Enter this code on GitHub:")
                    .foregroundStyle(.secondary)

                Text(code)
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .tracking(4)
                    .textSelection(.enabled)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 16)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.12)))

                HStack(spacing: 10) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                    } label: { Label("Copy code", systemImage: "doc.on.doc") }

                    Button {
                        if let url = URL(string: uri) { NSWorkspace.shared.open(url) }
                    } label: { Label("Open GitHub", systemImage: "safari") }
                        .buttonStyle(.borderedProminent)
                }

                Label("Waiting for you to authorize…", systemImage: "ellipsis.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            } else if let err = state.lastError {
                Text(err).foregroundStyle(.red).multilineTextAlignment(.center)
            } else {
                ProgressView()
            }

            Spacer(minLength: 0)
            Button("Cancel") { state.cancelAuth() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
