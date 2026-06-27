import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var showPrefs = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !showPrefs, case .signedIn = state.phase, let status = state.scanStatus {
                statusStrip(status)
            }
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            footer
        }
        .frame(width: 400, height: 500)   // fixed size → no resize jitter between refreshes
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gearshape.2.fill").foregroundStyle(.tint)
            Text("GitHub Workflows").font(.headline)
            if !showPrefs, case .signedIn = state.phase, state.runningCount > 0 {
                Text("\(state.runningCount)")
                    .font(.caption.bold())
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                    .foregroundStyle(.tint)
            }
            Spacer()
            if case .signedIn = state.phase {
                Button {
                    Task { await state.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(state.isRefreshing ? 360 : 0))
                        .animation(state.isRefreshing ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default,
                                   value: state.isRefreshing)
                }
                .buttonStyle(.borderless)
                .disabled(state.isRefreshing)
                .help("Refresh now")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private func statusStrip(_ status: String) -> some View {
        HStack(spacing: 7) {
            ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 14, height: 14)
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .contentTransition(.numericText())
                .animation(.default, value: status)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.bottom, 8)
        .transition(.opacity)
    }

    @ViewBuilder
    private var content: some View {
        if showPrefs {
            PreferencesView(onClose: { showPrefs = false })
        } else {
            switch state.phase {
            case .needsClientID:
                ClientIDView()
            case .signedOut:
                signedOutView
            case .awaitingAuth(let code, let uri):
                awaitingView(code: code, uri: uri)
            case .signedIn:
                runsList
            }
        }
    }

    private var signedOutView: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield").font(.largeTitle).foregroundStyle(.secondary)
            Text("Sign in to GitHub to see your running workflows.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Sign in with GitHub") { state.startDeviceFlow() }
                .buttonStyle(.borderedProminent)
            if let err = state.lastError {
                Text(err).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    private func awaitingView(code: String, uri: String) -> some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text("Enter this code on GitHub:").foregroundStyle(.secondary)
            Text(code)
                .font(.system(.title, design: .monospaced).bold())
                .textSelection(.enabled)
            Text("(Copied to clipboard — the page should have opened.)")
                .font(.caption).foregroundStyle(.secondary)
            Button("Open \(uri)") {
                if let url = URL(string: uri) { NSWorkspace.shared.open(url) }
            }
            .buttonStyle(.link)
            Button("Cancel") { state.signOut() }.buttonStyle(.borderless)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var runsList: some View {
        if state.runs.isEmpty && state.finished.isEmpty {
            if state.isRefreshing { loadingState } else { emptyState }
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    if !state.runs.isEmpty {
                        sectionHeader("RUNNING", count: state.runs.count)
                        ForEach(state.runs) { run in
                            RunRow(run: run)
                            Divider()
                        }
                    }
                    if !state.finished.isEmpty {
                        HStack {
                            sectionHeader("RECENTLY FINISHED", count: state.finished.count)
                            Spacer()
                            Button("Clear") { state.clearFinished() }
                                .font(.caption2).buttonStyle(.borderless)
                                .padding(.trailing, 12)
                        }
                        ForEach(state.finished) { fr in
                            FinishedRow(run: fr)
                            Divider()
                        }
                    }
                }
            }
            .onAppear { state.markFailuresSeen() }
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text("\(count)").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ForEach(0..<3, id: \.self) { _ in SkeletonRow() }
            Text(state.scanStatus ?? "Loading…")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 18)
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill").font(.largeTitle).foregroundStyle(.green)
            Text("All clear").font(.headline)
            Text("No workflows are running right now.")
                .font(.caption).foregroundStyle(.secondary)
            if let err = state.lastError {
                Text(err).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center).padding(.top, 4)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack {
            if case .signedIn(let login) = state.phase {
                Text("@\(login)").font(.caption).foregroundStyle(.secondary)
            }
            if let updated = state.lastUpdated {
                Text("· updated \(relative(updated))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button(showPrefs ? "Hide Preferences" : "Preferences…") { showPrefs.toggle() }
                if case .signedIn = state.phase {
                    Button("Sign out") { state.signOut() }
                }
                if AppConfig.clientID.isEmpty {
                    Button("Set Client ID…") { showPrefs = false; state.phase = .needsClientID }
                }
                Divider()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(12)
    }

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}

struct RunRow: View {
    let run: WorkflowRun
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summary
            if expanded { detail }
        }
    }

    // Collapsed summary — tap anywhere to expand/collapse.
    private var summary: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    statusIcon
                    Text(run.title).fontWeight(.medium).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(run.progressText)
                        .font(.caption).foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                    Image(systemName: "chevron.right")
                        .font(.caption2.bold())
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                progressBar
                HStack(spacing: 6) {
                    Text(run.repo).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if !run.branch.isEmpty {
                        Label(run.branch, systemImage: "arrow.triangle.branch")
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    if let job = run.activeJob {
                        Text(job.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    } else if let started = run.createdAt {
                        Text(elapsed(started)).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(expanded ? "Hide details" : "Show jobs")
    }

    @ViewBuilder
    private var progressBar: some View {
        if let frac = run.progressFraction {
            ProgressView(value: frac)
                .progressViewStyle(.linear)
                .tint(run.isQueued ? .gray : .accentColor)
        } else {
            // Indeterminate while jobs load / queued.
            ProgressView().progressViewStyle(.linear)
                .tint(run.isQueued ? .gray : .accentColor)
                .opacity(run.isQueued ? 0.4 : 1)
        }
    }

    // Expanded — per-job + current step, plus an Open-on-GitHub action.
    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !run.jobsLoaded {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                    Text("Loading jobs…").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
            } else if run.jobs.isEmpty {
                Text("No job data available yet.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.vertical, 8)
            } else {
                ForEach(run.jobs) { job in JobRow(job: job) }
            }

            Button {
                if let url = URL(string: run.htmlURL) { NSWorkspace.shared.open(url) }
            } label: {
                Label("Open run on GitHub", systemImage: "arrow.up.right.square")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 9)
        }
        .background(Color.primary.opacity(0.035))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    private var statusIcon: some View {
        if run.isQueued {
            Image(systemName: "clock.fill").foregroundStyle(.orange)
        } else {
            let icon = Image(systemName: "circle.dotted").foregroundStyle(.blue)
            if #available(macOS 14.0, *) {
                icon.symbolEffect(.pulse, options: .repeating)
            } else {
                icon
            }
        }
    }

    private func elapsed(_ start: Date) -> String {
        let s = max(0, Int(Date().timeIntervalSince(start)))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \((s % 3600) / 60)m"
    }
}

struct JobRow: View {
    let job: JobInfo

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            icon
            VStack(alignment: .leading, spacing: 1) {
                Text(job.name).font(.caption).fontWeight(.medium).lineLimit(1)
                Text(job.detail)
                    .font(.caption2)
                    .foregroundStyle(job.state == .failure ? .red : .secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 5)
    }

    @ViewBuilder
    private var icon: some View {
        if job.state == .running {
            ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 14, height: 14)
        } else {
            Image(systemName: job.state.symbol)
                .font(.caption)
                .foregroundStyle(job.state.tint)
                .frame(width: 14, height: 14)
        }
    }
}

struct FinishedRow: View {
    let run: FinishedRun

    var body: some View {
        Button {
            if let url = URL(string: run.htmlURL) { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: run.state.symbol)
                    .foregroundStyle(run.state.tint)
                    .font(.body)
                VStack(alignment: .leading, spacing: 1) {
                    Text(run.title).font(.callout).fontWeight(.medium).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(run.repo).lineLimit(1)
                        if !run.branch.isEmpty {
                            Text("· \(run.branch)").lineLimit(1)
                        }
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                Text(run.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(run.state.tint)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(run.state.tint.opacity(0.15)))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open run on GitHub")
    }
}

/// Shimmering placeholder shown during the first load.
struct SkeletonRow: View {
    @State private var shimmer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            bar(width: 180, height: 11)
            bar(width: .infinity, height: 6)
            bar(width: 120, height: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { shimmer = true }
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.secondary.opacity(0.15))
            .frame(maxWidth: width == .infinity ? .infinity : width)
            .frame(height: height)
            .opacity(shimmer ? 0.4 : 0.9)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: shimmer)
    }
}

struct ClientIDView: View {
    @EnvironmentObject var state: AppState
    @State private var draft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Set up GitHub OAuth App").font(.headline)
            Text("Create a GitHub OAuth App with **Device Flow enabled**, then paste its Client ID below. See README for the 1-minute setup.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Iv1.xxxxxxxxxxxxxxxx", text: $draft)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Open GitHub OAuth Apps") {
                    if let url = URL(string: "https://github.com/settings/developers") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
                Spacer()
                Button("Save") {
                    state.saveClientID(draft)
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .onAppear { draft = state.clientID }
    }
}

struct PreferencesView: View {
    @EnvironmentObject var state: AppState
    let onClose: () -> Void
    @State private var launchAtLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Preferences").font(.headline)
                Spacer()
                Button("Done", action: onClose).buttonStyle(.borderless)
            }

            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin },
                set: { launchAtLogin = $0; state.launchAtLogin = $0 }
            ))

            Toggle("Notify when a workflow finishes", isOn: Binding(
                get: { state.notifyEnabled },
                set: { state.notifyEnabled = $0; if $0 { Notifier.requestAuthorization() } }
            ))
            Toggle("Only notify on failures", isOn: $state.notifyFailuresOnly)
                .disabled(!state.notifyEnabled)
                .padding(.leading, 18)

            VStack(alignment: .leading, spacing: 4) {
                Text("Refresh every \(Int(state.refreshInterval))s").font(.subheadline)
                Slider(value: $state.refreshInterval, in: 10...120, step: 5)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Scan \(state.repoScanLimit) most-recent repos").font(.subheadline)
                Slider(
                    value: Binding(
                        get: { Double(state.repoScanLimit) },
                        set: { state.repoScanLimit = Int($0) }
                    ),
                    in: 10...100, step: 5
                )
                Text("Higher = more coverage, more API usage.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider()
            HStack {
                Text("GitHub Workflows v1.0").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Apply & Refresh") {
                    state.startAutoRefresh()
                    Task { await state.refresh() }
                    onClose()
                }
                .buttonStyle(.bordered)
                .disabled(!state.isSignedIn)
            }
        }
        .padding(20)
        .onAppear { launchAtLogin = state.launchAtLogin }
    }
}
