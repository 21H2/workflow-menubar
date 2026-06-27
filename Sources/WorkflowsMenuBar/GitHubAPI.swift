import Foundation

enum GitHubError: LocalizedError {
    case http(Int, String)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let body): return "HTTP \(code): \(body)"
        case .message(let m): return m
        }
    }
}

/// Talks to GitHub's OAuth device-flow and REST APIs.
struct GitHubAPI {
    let clientID: String
    var token: String?

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - OAuth device flow

    func requestDeviceCode(scope: String = "repo") async throws -> DeviceCodeResponse {
        var req = URLRequest(url: URL(string: "https://github.com/login/device/code")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = "client_id=\(clientID)&scope=\(scope)".data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.checkStatus(resp, data)
        return try Self.decoder.decode(DeviceCodeResponse.self, from: data)
    }

    /// Polls once for the access token. Returns the token, or nil if still pending.
    /// Throws on a terminal error (denied, expired, etc.).
    func pollForToken(deviceCode: String) async throws -> String? {
        var req = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let grant = "urn:ietf:params:oauth:grant-type:device_code"
        req.httpBody = "client_id=\(clientID)&device_code=\(deviceCode)&grant_type=\(grant)".data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.checkStatus(resp, data)
        let result = try Self.decoder.decode(AccessTokenResponse.self, from: data)
        if let tok = result.accessToken { return tok }
        switch result.error {
        case "authorization_pending", "slow_down", .none:
            return nil
        default:
            throw GitHubError.message(result.errorDescription ?? result.error ?? "Authorization failed")
        }
    }

    // MARK: - REST

    private func authedRequest(_ url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return req
    }

    func currentUser() async throws -> GitHubUser {
        let (data, resp) = try await URLSession.shared.data(for: authedRequest(URL(string: "https://api.github.com/user")!))
        try Self.checkStatus(resp, data)
        return try Self.decoder.decode(GitHubUser.self, from: data)
    }

    /// Most recently pushed repositories the user can access.
    func recentRepositories(limit: Int) async throws -> [Repository] {
        let url = URL(string: "https://api.github.com/user/repos?per_page=\(min(limit,100))&sort=pushed&affiliation=owner,collaborator,organization_member")!
        let (data, resp) = try await URLSession.shared.data(for: authedRequest(url))
        try Self.checkStatus(resp, data)
        return try Self.decoder.decode([Repository].self, from: data)
    }

    /// Active (queued + in_progress) runs for a repo.
    func activeRuns(repo: String) async throws -> [WorkflowRunDTO] {
        async let inProgress = runs(repo: repo, status: "in_progress")
        async let queued = runs(repo: repo, status: "queued")
        return try await inProgress + queued
    }

    private func runs(repo: String, status: String) async throws -> [WorkflowRunDTO] {
        let url = URL(string: "https://api.github.com/repos/\(repo)/actions/runs?status=\(status)&per_page=20")!
        let (data, resp) = try await URLSession.shared.data(for: authedRequest(url))
        try Self.checkStatus(resp, data)
        return try Self.decoder.decode(WorkflowRunsResponse.self, from: data).workflowRuns
    }

    /// A single run, used to read the final conclusion once it leaves the active set.
    func run(repo: String, id: Int) async throws -> WorkflowRunDTO {
        let url = URL(string: "https://api.github.com/repos/\(repo)/actions/runs/\(id)")!
        let (data, resp) = try await URLSession.shared.data(for: authedRequest(url))
        try Self.checkStatus(resp, data)
        return try Self.decoder.decode(WorkflowRunDTO.self, from: data)
    }

    func jobs(repo: String, runID: Int) async throws -> JobsResponse {
        let url = URL(string: "https://api.github.com/repos/\(repo)/actions/runs/\(runID)/jobs?per_page=100")!
        let (data, resp) = try await URLSession.shared.data(for: authedRequest(url))
        try Self.checkStatus(resp, data)
        return try Self.decoder.decode(JobsResponse.self, from: data)
    }

    private static func checkStatus(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GitHubError.http(http.statusCode, String(body.prefix(200)))
        }
    }
}
