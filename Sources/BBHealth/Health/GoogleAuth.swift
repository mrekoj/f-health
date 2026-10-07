import Foundation
import Observation
import CryptoKit
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

/// Đăng nhập Google bằng OAuth 2.0 + PKCE (client iOS, **không có client secret**).
/// Dùng `ASWebAuthenticationSession`; token lưu Keychain; tự làm mới khi hết hạn.
///
/// iOS OAuth client của Google dùng **scheme đảo ngược của Client ID** làm redirect
/// (vd Client ID `123-abc.apps.googleusercontent.com` → scheme `com.googleusercontent.apps.123-abc`).
/// App tự suy ra scheme này từ Client ID người dùng dán vào, không cần cấu hình thêm.
@MainActor
@Observable
final class GoogleAuth {
    static let shared = GoogleAuth()

    /// Ba scope chỉ-đọc đủ cho ngủ/bước/nhịp tim/HRV/cân/SpO2/nhiệt độ da.
    static let scopes = [
        "https://www.googleapis.com/auth/googlehealth.sleep.readonly",
        "https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly",
        "https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly",
    ]

    private enum Account {
        static let refresh = "refreshToken"
        static let access = "accessToken"
        static let expiry = "accessExpiry"
    }

    /// Đã đăng nhập chưa (có refresh token). Trên simulator: cờ giả để chụp màn hình.
    private(set) var isConnected: Bool

    private var accessToken: String?
    private var accessExpiry: Date?

    #if canImport(AuthenticationServices)
    private let presenter = WebAuthPresenter()
    #endif

    init() {
        if HealthStoreFactory.useMock {
            isConnected = UserDefaults.standard.bool(forKey: "bbh.google.mockConnected")
        } else {
            isConnected = Keychain.get(Account.refresh) != nil
            accessToken = Keychain.get(Account.access)
            accessExpiry = (Keychain.get(Account.expiry)).flatMap { TimeInterval($0) }.map { Date(timeIntervalSince1970: $0) }
        }
    }

    enum AuthError: LocalizedError {
        case missingClientID, notConnected, badResponse, cancelled, server(String)
        var errorDescription: String? {
            switch self {
            case .missingClientID: return "Chưa nhập Google Client ID. Vào Cài đặt để dán mã."
            case .notConnected: return "Chưa đăng nhập Google."
            case .badResponse: return "Google trả về dữ liệu không đọc được."
            case .cancelled: return "Đã huỷ đăng nhập."
            case .server(let m): return "Google báo lỗi: \(m)"
            }
        }
    }

    // MARK: - Đăng nhập / đăng xuất

    /// Mở trang đăng nhập Google, đổi mã lấy token. `clientID` dạng `NNN-xxxx.apps.googleusercontent.com`.
    func signIn(clientID: String) async throws {
        // Client ID không bao giờ chứa ký tự trắng → bỏ hết (dán kèm xuống dòng/khoảng trắng làm Google báo 400).
        let clientID = Self.cleanClientID(clientID)
        guard !clientID.isEmpty else { throw AuthError.missingClientID }
        guard clientID.hasSuffix(".apps.googleusercontent.com"), !clientID.hasPrefix("AIza"), !clientID.hasPrefix("AQ.") else {
            throw AuthError.server("Client ID không đúng dạng (phải kết thúc bằng .apps.googleusercontent.com — không phải khoá Gemini AQ.… / AIza…; khoá Gemini dán ở Cài đặt → Trợ lý AI). Kiểm tra lại ô Google OAuth Client ID.")
        }

        // Simulator/mock: bỏ qua OAuth thật để chụp màn hình được.
        if HealthStoreFactory.useMock {
            try? await Task.sleep(for: .milliseconds(600))
            isConnected = true
            UserDefaults.standard.set(true, forKey: "bbh.google.mockConnected")
            return
        }

        #if canImport(AuthenticationServices)
        let verifier = Self.randomURLSafe(64)
        let challenge = Self.codeChallenge(for: verifier)
        let scheme = Self.reversedScheme(clientID: clientID)
        let redirectURI = "\(scheme):/oauth2redirect"

        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: Self.scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
        ]

        let callbackURL = try await presenter.start(url: comps.url!, callbackScheme: scheme)
        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AuthError.cancelled
        }
        try await exchangeCode(code, verifier: verifier, clientID: clientID, redirectURI: redirectURI)
        isConnected = true
        #else
        throw AuthError.badResponse
        #endif
    }

    /// Bỏ mọi khoảng trắng/xuống dòng trong Client ID.
    nonisolated static func cleanClientID(_ s: String) -> String {
        s.components(separatedBy: .whitespacesAndNewlines).joined()
    }

    func signOut() {
        accessToken = nil
        accessExpiry = nil
        isConnected = false
        if HealthStoreFactory.useMock {
            UserDefaults.standard.set(false, forKey: "bbh.google.mockConnected")
        } else {
            Keychain.remove(Account.refresh)
            Keychain.remove(Account.access)
            Keychain.remove(Account.expiry)
        }
    }

    // MARK: - Token còn hạn

    /// Trả access token còn hạn; tự làm mới bằng refresh token nếu cần.
    func validAccessToken() async throws -> String {
        if let token = accessToken, let exp = accessExpiry, exp.timeIntervalSinceNow > 60 {
            return token
        }
        guard let refresh = Keychain.get(Account.refresh) else { throw AuthError.notConnected }
        let clientID = Self.cleanClientID(AppSettings.shared.googleClientID)
        guard !clientID.isEmpty else { throw AuthError.missingClientID }
        try await refreshToken(refresh, clientID: clientID)
        guard let token = accessToken else { throw AuthError.notConnected }
        return token
    }

    // MARK: - Gọi endpoint token

    private func exchangeCode(_ code: String, verifier: String, clientID: String, redirectURI: String) async throws {
        let form = [
            "code": code,
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier,
        ]
        let json = try await postToken(form)
        if let refresh = json["refresh_token"] as? String { Keychain.set(refresh, for: Account.refresh) }
        store(access: json)
    }

    private func refreshToken(_ refresh: String, clientID: String) async throws {
        let form = [
            "refresh_token": refresh,
            "client_id": clientID,
            "grant_type": "refresh_token",
        ]
        let json = try await postToken(form)
        store(access: json)
    }

    private func postToken(_ form: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form.map { "\($0.key)=\(Self.escape($0.value))" }.joined(separator: "&").data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.badResponse
        }
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            let msg = (json["error_description"] as? String) ?? (json["error"] as? String) ?? "HTTP \(http.statusCode)"
            throw AuthError.server(msg)
        }
        return json
    }

    private func store(access json: [String: Any]) {
        if let token = json["access_token"] as? String {
            accessToken = token
            Keychain.set(token, for: Account.access)
        }
        if let expiresIn = json["expires_in"] as? Double {
            let exp = Date().addingTimeInterval(expiresIn)
            accessExpiry = exp
            Keychain.set(String(exp.timeIntervalSince1970), for: Account.expiry)
        }
    }

    // MARK: - PKCE + tiện ích

    /// Scheme redirect iOS = Client ID đảo ngược (bỏ hậu tố `.apps.googleusercontent.com`).
    static func reversedScheme(clientID: String) -> String {
        let base = clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        return "com.googleusercontent.apps.\(base)"
    }

    private static func randomURLSafe(_ count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func escape(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}

#if canImport(AuthenticationServices)
/// Bọc `ASWebAuthenticationSession` thành async/await, có anchor cửa sổ.
@MainActor
final class WebAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    func start(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callback, error in
                if let callback {
                    cont.resume(returning: callback)
                } else if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(throwing: GoogleAuth.AuthError.cancelled)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first(where: { $0.isKeyWindow }) ?? scenes.first?.windows.first
        return window ?? ASPresentationAnchor()
    }
}
#endif
