import Foundation
import SwiftUI
import AppKit
import ServiceManagement

@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable {
        case needsClientID
        case signedOut
        case awaitingAuth(userCode: String, verificationUri: String)
        case signedIn(login: String)
    }

    @Published var phase: Phase = .signedOut {
        didSet { syncAuthWindow() }
    }
    @Published var runs: [WorkflowRun] = []
    @Published var finished: [FinishedRun] = []
    @Published var unseenFailures: Int = 0
    @Published var isRefreshing = false
    @Published var scanStatus: String?
    @Published var lastUpdated: Date?
    @Published var lastError: String?

    @AppStorage("clientID") var clientID: String = ""
    @AppStorage("repoScanLimit") var repoScanLimit: Int = 40
    @AppStorage("refreshInterval") var refreshInterval: Double = 20
    @AppStorage("notifyEnabled") var notifyEnabled: Bool = true
    @AppStorage("notifyFailuresOnly") var notifyFailuresOnly: Bool = false

    private var token: String?
    private var pollTask: Task<Void, Never>?
    private var refreshTimer: Timer?
    /// Active runs seen on the previous refresh, to detect just-finished runs.
    private var lastActive: [Int: WorkflowRunDTO] = [:]
    private let authWindow = AuthWindowController()

    private func syncAuthWindow() {
        if case .awaitingAuth = phase {
            authWindow.show(state: self)
        } else {
            authWindow.close()
        }
    }

    var runningCount: Int { runs.count }

    var isSignedIn: Bool {
        if case .signedIn = phase { return true }
        return false
    }

    /// Build-time/baked-in Client ID, unless the user overrode it in Preferences.
    var effectiveClientID: String {
        clientID.isEmpty ? AppConfig.clientID : clientID
    }

    private var api: GitHubAPI { GitHubAPI(clientID: effectiveClientID, token: token) }

    // MARK: - Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
                objectWillChange.send()
            } catch {
                lastError = "Couldn't update Launch at Login: \(error.localizedDescription)"
            }
        }
    }

    func bootstrap() {
        token = Keychain.load()
        if effectiveClientID.isEmpty {
            phase = .needsClientID
        } else if token != nil {
            phase = .signedIn(login: "…")
            Task { await self.verifyAndStart() }
        } else {
            phase = .signedOut
        }
    }

    private func verifyAndStart() async {
        do {
            let user = try await api.currentUser()
            phase = .signedIn(login: user.login)
            if notifyEnabled { Notifier.requestAuthorization() }
            startAutoRefresh()
            await refresh()
        } catch {
            // Token invalid/expired.
            signOut()
            lastError = "Saved session expired. Please sign in again."
        }
    }

    // MARK: - Auth

    func saveClientID(_ id: String) {
        clientID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = token != nil ? .signedIn(login: "…") : .signedOut
    }

    func startDeviceFlow() {
        guard !effectiveClientID.isEmpty else { phase = .needsClientID; return }
        lastError = nil
        pollTask?.cancel()
        pollTask = Task {
            do {
                let device = try await api.requestDeviceCode(scope: AppConfig.scope)
                phase = .awaitingAuth(userCode: device.userCode, verificationUri: device.verificationUri)
                // Open the verification page and copy the code for convenience.
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(device.userCode, forType: .string)
                if let url = URL(string: device.verificationUri) { NSWorkspace.shared.open(url) }

                let deadline = Date().addingTimeInterval(TimeInterval(device.expiresIn))
                let interval = UInt64(max(device.interval, 5))
                while Date() < deadline {
                    try? await Task.sleep(nanoseconds: interval * 1_000_000_000)
                    if Task.isCancelled { return }
                    do {
                        if let tok = try await api.pollForToken(deviceCode: device.deviceCode) {
                            token = tok
                            Keychain.save(tok)
                            await verifyAndStart()
                            return
                        }
                    } catch {
                        lastError = error.localizedDescription
                        phase = .signedOut
                        return
                    }
                }
                lastError = "Device code expired. Try signing in again."
                phase = .signedOut
            } catch {
                lastError = error.localizedDescription
                phase = .signedOut
            }
        }
    }

    /// Abort an in-progress device-flow sign-in (Cancel button / closed window).
    func cancelAuth() {
        pollTask?.cancel()
        lastError = nil
        phase = .signedOut
    }

    func signOut() {
        pollTask?.cancel()
        stopAutoRefresh()
        Keychain.delete()
        token = nil
        runs = []
        finished = []
        unseenFailures = 0
        lastActive = [:]
        lastUpdated = nil
        phase = .signedOut
    }

    // MARK: - Polling

    func startAutoRefresh() {
        stopAutoRefresh()
        let timer = Timer.scheduledTimer(withTimeInterval: max(refreshInterval, 10), repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refresh() async {
        guard token != nil, !isRefreshing else { return }
        isRefreshing = true
        scanStatus = "Finding your repositories…"
        defer { isRefreshing = false; scanStatus = nil }
        do {
            let api = self.api
            let repos = try await api.recentRepositories(limit: repoScanLimit)
            let names = repos.map { $0.fullName }
            scanStatus = "Scanning \(names.count) repositories…"

            // Phase 1 — discover active runs, streaming progress as repos report in.
            var discovered: [WorkflowRunDTO] = []
            var scanned = 0
            await withTaskGroup(of: [WorkflowRunDTO].self) { group in
                var index = 0
                let maxConcurrent = 10
                func addNext() {
                    guard index < names.count else { return }
                    let repo = names[index]; index += 1
                    group.addTask { (try? await api.activeRuns(repo: repo)) ?? [] }
                }
                for _ in 0..<min(maxConcurrent, names.count) { addNext() }
                for await result in group {
                    scanned += 1
                    discovered.append(contentsOf: result)
                    scanStatus = "Scanned \(scanned)/\(names.count) repos · \(discovered.count) active"
                    addNext()
                }
            }

            // Publish placeholders right away so runs appear instantly.
            let placeholders = discovered
                .map { Self.makeRun(dto: $0) }
                .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            withAnimation(.easeOut(duration: 0.2)) {
                self.reconcile(with: placeholders)
            }
            self.lastError = nil

            // Detect runs that just transitioned active → finished.
            await detectFinishedRuns(currentlyActive: discovered, api: api)

            guard !discovered.isEmpty else {
                self.lastUpdated = Date()
                return
            }

            // Phase 2 — enrich each run with job/step detail, updating as they load.
            scanStatus = "Loading job details…"
            await withTaskGroup(of: WorkflowRun.self) { group in
                for dto in discovered { group.addTask { await Self.enrich(dto: dto, api: api) } }
                for await run in group {
                    withAnimation(.easeInOut(duration: 0.15)) { self.upsert(run) }
                }
            }
            self.lastUpdated = Date()
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    /// Compare the active set against the previous one; anything that left is "finished".
    private func detectFinishedRuns(currentlyActive: [WorkflowRunDTO], api: GitHubAPI) async {
        let activeNow = Dictionary(currentlyActive.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let previous = lastActive
        lastActive = activeNow
        if previous.isEmpty { return }   // first scan establishes a baseline — don't notify

        let finishedIDs = previous.keys.filter { activeNow[$0] == nil }
        for id in finishedIDs {
            guard let prev = previous[id], let repo = prev.repository?.fullName else { continue }
            let conclusion = (try? await api.run(repo: repo, id: id))?.conclusion ?? "completed"
            recordFinished(FinishedRun(
                id: id,
                title: prev.displayTitle ?? prev.name ?? "Workflow run",
                repo: repo,
                branch: prev.headBranch ?? "",
                conclusion: conclusion,
                htmlURL: prev.htmlUrl,
                finishedAt: Date()
            ))
        }
    }

    private func recordFinished(_ fr: FinishedRun) {
        withAnimation(.easeInOut(duration: 0.2)) {
            finished.removeAll { $0.id == fr.id }
            finished.insert(fr, at: 0)
            if finished.count > 20 { finished = Array(finished.prefix(20)) }
        }
        if fr.isFailure { unseenFailures += 1 }
        if notifyEnabled && (!notifyFailuresOnly || fr.isFailure) {
            let emoji = fr.state == .success ? "✅" : (fr.isFailure ? "❌" : "⚪️")
            Notifier.notify(
                title: "\(emoji) \(fr.label): \(fr.repo)",
                body: fr.branch.isEmpty ? fr.title : "\(fr.title) · \(fr.branch)",
                id: "run-\(fr.id)"
            )
        }
    }

    func clearFinished() {
        withAnimation { finished.removeAll() }
        unseenFailures = 0
    }

    func markFailuresSeen() { unseenFailures = 0 }

    /// Replace the list while keeping already-enriched runs from flickering back to placeholders.
    private func reconcile(with incoming: [WorkflowRun]) {
        let existing = Dictionary(uniqueKeysWithValues: runs.map { ($0.id, $0) })
        runs = incoming.map { new in
            if let old = existing[new.id], old.jobsLoaded { return old }
            return new
        }
    }

    private func upsert(_ run: WorkflowRun) {
        if let i = runs.firstIndex(where: { $0.id == run.id }) {
            runs[i] = run
        } else {
            runs.append(run)
            runs.sort { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        }
    }

    private static func makeRun(dto: WorkflowRunDTO) -> WorkflowRun {
        WorkflowRun(
            id: dto.id,
            title: dto.displayTitle ?? dto.name ?? "Workflow run",
            repo: dto.repository?.fullName ?? "?",
            branch: dto.headBranch ?? "",
            event: dto.event ?? "",
            status: dto.status ?? "",
            htmlURL: dto.htmlUrl,
            createdAt: dto.createdAt,
            jobs: [],
            jobsLoaded: false
        )
    }

    private static func enrich(dto: WorkflowRunDTO, api: GitHubAPI) async -> WorkflowRun {
        var run = makeRun(dto: dto)
        if let resp = try? await api.jobs(repo: run.repo, runID: dto.id) {
            run.jobs = resp.jobs.map { JobInfo(from: $0) }
        }
        run.jobsLoaded = true
        return run
    }
}
