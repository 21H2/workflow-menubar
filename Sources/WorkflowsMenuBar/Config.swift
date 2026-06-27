import Foundation

/// App configuration for distribution.
///
/// ▶ TO SHIP THIS APP: paste your GitHub OAuth App's Client ID below.
///   (Create one at https://github.com/settings/developers — "New OAuth App",
///    then enable "Device Flow". The Client ID is NOT a secret, so it is safe
///    to embed here.)
///
/// You can also inject it at build time without editing this file:
///     GH_CLIENT_ID=Iv1.xxxxxxxx ./build-app.sh
/// which generates Config.generated.swift and overrides this value.
enum AppConfig {
    /// Paste your Client ID here (e.g. "Iv1.0123456789abcdef" or "Ov23li...").
    static let bakedInClientID = ""

    /// OAuth scope. `repo` is needed to read runs in private repos.
    /// Use `public_repo` if you only need public repositories.
    static let scope = "repo"

    /// The effective Client ID: a build-time injected value wins, otherwise the
    /// pasted value above.
    static var clientID: String {
        let injected = GeneratedConfig.injectedClientID
        return injected.isEmpty ? bakedInClientID : injected
    }
}
