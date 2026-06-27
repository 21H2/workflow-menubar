import Foundation
import SwiftUI

// MARK: - OAuth Device Flow

struct DeviceCodeResponse: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationUri: String
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationUri = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

struct AccessTokenResponse: Decodable {
    let accessToken: String?
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case error
        case errorDescription = "error_description"
    }
}

// MARK: - REST API models

struct GitHubUser: Decodable {
    let login: String
}

struct Repository: Decodable {
    let fullName: String
    let pushedAt: Date?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case pushedAt = "pushed_at"
    }
}

struct WorkflowRunsResponse: Decodable {
    let workflowRuns: [WorkflowRunDTO]

    enum CodingKeys: String, CodingKey {
        case workflowRuns = "workflow_runs"
    }
}

struct WorkflowRunDTO: Decodable {
    let id: Int
    let name: String?
    let displayTitle: String?
    let status: String?       // queued, in_progress, completed
    let conclusion: String?   // success, failure, cancelled, ...
    let htmlUrl: String
    let headBranch: String?
    let event: String?
    let runNumber: Int?
    let createdAt: Date?
    let repository: RepoRef?

    enum CodingKeys: String, CodingKey {
        case id, name, status, conclusion, event
        case displayTitle = "display_title"
        case htmlUrl = "html_url"
        case headBranch = "head_branch"
        case runNumber = "run_number"
        case createdAt = "created_at"
        case repository
    }
}

struct RepoRef: Decodable {
    let fullName: String
    enum CodingKeys: String, CodingKey { case fullName = "full_name" }
}

struct JobsResponse: Decodable {
    let totalCount: Int
    let jobs: [JobDTO]

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case jobs
    }
}

struct JobDTO: Decodable {
    let id: Int
    let name: String
    let status: String        // queued, in_progress, completed
    let conclusion: String?
    let steps: [StepDTO]?
}

struct StepDTO: Decodable {
    let name: String
    let status: String        // queued, in_progress, completed
    let conclusion: String?
    let number: Int
}

// MARK: - View model

enum JobState {
    case queued, running, success, failure, neutral

    var symbol: String {
        switch self {
        case .queued: return "clock"
        case .running: return "circle.dotted"
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        case .neutral: return "minus.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .queued: return .orange
        case .running: return .blue
        case .success: return .green
        case .failure: return .red
        case .neutral: return .secondary
        }
    }
}

struct JobInfo: Identifiable {
    let id: Int
    let name: String
    let status: String          // queued, in_progress, completed
    let conclusion: String?
    let currentStep: String?    // name of the in-progress step, if any
    let stepsCompleted: Int
    let stepsTotal: Int

    init(from dto: JobDTO) {
        id = dto.id
        name = dto.name
        status = dto.status
        conclusion = dto.conclusion
        let steps = dto.steps ?? []
        currentStep = steps.first { $0.status == "in_progress" }?.name
        stepsCompleted = steps.filter { $0.status == "completed" }.count
        stepsTotal = steps.count
    }

    var state: JobState {
        switch status {
        case "queued": return .queued
        case "in_progress": return .running
        case "completed":
            switch conclusion {
            case "success": return .success
            case "failure", "timed_out": return .failure
            default: return .neutral
            }
        default: return .running
        }
    }

    var detail: String {
        if status == "in_progress", let step = currentStep {
            return stepsTotal > 0 ? "\(step) · step \(stepsCompleted + 1)/\(stepsTotal)" : step
        }
        if status == "completed" { return conclusion ?? "done" }
        return status.replacingOccurrences(of: "_", with: " ")
    }
}

struct WorkflowRun: Identifiable {
    let id: Int
    let title: String
    let repo: String
    let branch: String
    let event: String
    let status: String          // queued, in_progress
    let htmlURL: String
    let createdAt: Date?
    var jobs: [JobInfo]
    var jobsLoaded: Bool

    var totalJobs: Int { jobs.count }
    var completedJobs: Int { jobs.filter { $0.status == "completed" }.count }

    /// nil = indeterminate (jobs not loaded yet).
    var progressFraction: Double? {
        guard jobsLoaded, totalJobs > 0 else { return nil }
        return Double(completedJobs) / Double(totalJobs)
    }

    var progressText: String {
        if !jobsLoaded { return "loading…" }
        if totalJobs == 0 { return status == "queued" ? "queued" : status }
        return "\(completedJobs)/\(totalJobs) jobs"
    }

    /// The job currently doing work, for the collapsed summary line.
    var activeJob: JobInfo? {
        jobs.first { $0.status == "in_progress" }
    }

    var isQueued: Bool { status == "queued" }
}

/// A run that recently transitioned from active → completed.
struct FinishedRun: Identifiable {
    let id: Int
    let title: String
    let repo: String
    let branch: String
    let conclusion: String      // success, failure, cancelled, skipped, timed_out…
    let htmlURL: String
    let finishedAt: Date

    var state: JobState {
        switch conclusion {
        case "success": return .success
        case "failure", "timed_out", "startup_failure": return .failure
        default: return .neutral
        }
    }

    var label: String {
        switch conclusion {
        case "success": return "Passed"
        case "failure": return "Failed"
        case "timed_out": return "Timed out"
        case "cancelled": return "Cancelled"
        case "startup_failure": return "Startup failure"
        default: return conclusion.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var isFailure: Bool { state == .failure }
}
