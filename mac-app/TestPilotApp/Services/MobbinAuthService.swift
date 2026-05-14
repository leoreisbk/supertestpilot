import Foundation
import Network
import AppKit
import CryptoKit
import Observation

private enum MobbinOAuth {
    static let clientId    = "adac7b54-3d18-4eee-a494-289b38e12e8e"
    static let redirectURI = "http://localhost:9898/callback"
    static let callbackPort: NWEndpoint.Port = 9898
    static let authURL  = URL(string: "https://ujasntkfphywizsdaapi.supabase.co/auth/v1/oauth/authorize")!
    static let tokenURL = URL(string: "https://ujasntkfphywizsdaapi.supabase.co/auth/v1/oauth/token")!
}

enum MobbinAuthError: LocalizedError {
    case callbackTimeout
    case callbackMissingCode
    case tokenExchangeFailed(String)
    case tokenRefreshFailed
    case portInUse

    var errorDescription: String? {
        switch self {
        case .callbackTimeout:            return "Mobbin login timed out. Please try again."
        case .callbackMissingCode:        return "OAuth callback did not return an authorization code."
        case .tokenExchangeFailed(let m): return "Token exchange failed: \(m)"
        case .tokenRefreshFailed:         return "Mobbin session expired — reconnect in Settings."
        case .portInUse:                  return "Port 9898 is busy. Close other apps and try again."
        }
    }
}

@MainActor
@Observable
final class MobbinAuthService {
    private(set) var isConnected: Bool = false
    private(set) var isAuthenticating: Bool = false
    private(set) var lastError: String? = nil

    private let kcService = "com.workco.testpilot.mobbin"

    init() {
        isConnected = keychainLoad("access_token") != nil
    }

    var accessToken: String? { keychainLoad("access_token") }

    func disconnect() {
        keychainDelete("access_token")
        keychainDelete("refresh_token")
        isConnected = false
    }

    // MARK: - OAuth flow

    func startOAuthFlow() async {
        isAuthenticating = true
        lastError = nil
        defer { isAuthenticating = false }

        let verifier  = makeCodeVerifier()
        let challenge = makeCodeChallenge(verifier)
        let state     = UUID().uuidString.replacingOccurrences(of: "-", with: "")

        var comps = URLComponents(url: MobbinOAuth.authURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "client_id",             value: MobbinOAuth.clientId),
            URLQueryItem(name: "response_type",         value: "code"),
            URLQueryItem(name: "redirect_uri",          value: MobbinOAuth.redirectURI),
            URLQueryItem(name: "scope",                 value: "openid"),
            URLQueryItem(name: "code_challenge",        value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state",                 value: state),
        ]
        guard let authURL = comps.url else { lastError = "Failed to build auth URL"; return }

        do {
            async let codeFuture = waitForCallback()
            NSWorkspace.shared.open(authURL)
            let code = try await codeFuture

            let token = try await exchangeCode(code, verifier: verifier)
            keychainSave(token.access_token, account: "access_token")
            if let rt = token.refresh_token { keychainSave(rt, account: "refresh_token") }
            isConnected = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - PKCE

    private func makeCodeVerifier() -> String {
        var b = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, b.count, &b)
        return Data(b).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func makeCodeChallenge(_ verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Callback server

    private func waitForCallback() async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            var listener: NWListener?
            var done = false
            let finish: (Result<String, Error>) -> Void = { result in
                guard !done else { return }
                done = true
                listener?.cancel()
                cont.resume(with: result)
            }

            do {
                listener = try NWListener(using: .tcp, on: MobbinOAuth.callbackPort)
            } catch {
                cont.resume(throwing: MobbinAuthError.portInUse)
                return
            }

            listener?.newConnectionHandler = { conn in
                conn.start(queue: .global())
                conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                    let html = "<html><body style='font-family:system-ui;text-align:center;padding:60px'><h2>✓ Connected to Mobbin</h2><p>Return to TestPilot.</p></body></html>"
                    let resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
                    conn.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })

                    guard let raw = data.flatMap({ String(data: $0, encoding: .utf8) }),
                          let code = Self.extractParam("code", from: raw)
                    else { finish(.failure(MobbinAuthError.callbackMissingCode)); return }
                    finish(.success(code))
                }
            }

            listener?.start(queue: .global())

            DispatchQueue.global().asyncAfter(deadline: .now() + 300) {
                finish(.failure(MobbinAuthError.callbackTimeout))
            }
        }
    }

    private static func extractParam(_ name: String, from httpRequest: String) -> String? {
        guard let line = httpRequest.components(separatedBy: "\r\n").first,
              let path = line.components(separatedBy: " ").dropFirst().first,
              let comps = URLComponents(string: "http://localhost" + path)
        else { return nil }
        return comps.queryItems?.first { $0.name == name }?.value
    }

    // MARK: - Token exchange

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int?
    }

    private func exchangeCode(_ code: String, verifier: String) async throws -> TokenResponse {
        var req = URLRequest(url: MobbinOAuth.tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "grant_type":    "authorization_code",
            "code":          code,
            "redirect_uri":  MobbinOAuth.redirectURI,
            "client_id":     MobbinOAuth.clientId,
            "code_verifier": verifier,
        ]
        req.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
                           .joined(separator: "&").data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw MobbinAuthError.tokenExchangeFailed(String(data: data, encoding: .utf8) ?? "HTTP error")
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    // MARK: - Keychain

    private func keychainLoad(_ account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: kcService,
                                kSecAttrAccount as String: account,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    private func keychainSave(_ value: String, account: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: kcService,
                                kSecAttrAccount as String: account]
        let d = Data(value.utf8)
        if SecItemUpdate(q as CFDictionary, [kSecValueData as String: d] as CFDictionary) == errSecItemNotFound {
            var add = q; add[kSecValueData as String] = d
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private func keychainDelete(_ account: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: kcService,
                       kSecAttrAccount as String: account] as CFDictionary)
    }
}
