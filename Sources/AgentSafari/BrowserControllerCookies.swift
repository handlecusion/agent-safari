import AgentSafariCore
import Foundation
import WebKit

// Cookie JSON schema version for export/import files.
// Bump when the schema changes in a backward-incompatible way.
private let cookieSchemaVersion = 1

// Cookies are session-wide (one WKWebsiteDataStore per daemon, shared across
// all tabs). The --tab flag has no effect on these commands.

@MainActor
extension BrowserController {

    // MARK: - Export

    /// Export all cookies from the daemon's websiteDataStore to a JSON file.
    ///
    /// The file is written with 0600 permissions because it contains credentials.
    /// Schema:
    ///   { "schemaVersion": 1, "cookies": [ { name, value, domain, path,
    ///     expiresEpoch?, secure, httpOnly, sameSite? } ] }
    func cookiesExport(path: String) async throws -> [String: String] {
        let store = webView.configuration.websiteDataStore.httpCookieStore
        let cookies: [HTTPCookie] = try await withCheckedThrowingContinuation { cont in
            store.getAllCookies { cookies in
                cont.resume(returning: cookies)
            }
        }

        var cookieArray: [[String: Any]] = []
        for cookie in cookies {
            var entry: [String: Any] = [
                "name": cookie.name,
                "value": cookie.value,
                "domain": cookie.domain,
                "path": cookie.path,
                "secure": cookie.isSecure,
                "httpOnly": cookie.isHTTPOnly,
            ]
            if let expiresDate = cookie.expiresDate {
                entry["expiresEpoch"] = expiresDate.timeIntervalSince1970
            }
            if let sameSite = cookie.sameSitePolicy {
                switch sameSite {
                case .sameSiteLax: entry["sameSite"] = "lax"
                case .sameSiteStrict: entry["sameSite"] = "strict"
                default: break
                }
            }
            cookieArray.append(entry)
        }

        let payload: [String: Any] = [
            "schemaVersion": cookieSchemaVersion,
            "cookies": cookieArray,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])

        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        // chmod 0600: cookies are credentials
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)

        return ["path": url.path, "count": String(cookies.count)]
    }

    // MARK: - Import

    /// Import cookies from a previously-exported JSON file into the daemon's
    /// websiteDataStore. Cookies are session-wide; all tabs share them.
    ///
    /// Errors:
    ///   - `AgentSafariError.cookieFileInvalid` for malformed JSON or missing
    ///     required fields (name, value, domain, path).
    ///   - Foundation file errors if the file does not exist or is unreadable.
    func cookiesImport(path: String) async throws -> [String: String] {
        let url = URL(fileURLWithPath: path)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw AgentSafariError.cookieFileInvalid("Cannot read file at \(path): \(error.localizedDescription)")
        }

        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw AgentSafariError.cookieFileInvalid("JSON parse error: \(error.localizedDescription)")
        }

        guard let root = json as? [String: Any] else {
            throw AgentSafariError.cookieFileInvalid("Root must be a JSON object")
        }
        guard let cookieList = root["cookies"] as? [[String: Any]] else {
            throw AgentSafariError.cookieFileInvalid("Missing or invalid \"cookies\" array")
        }

        let store = webView.configuration.websiteDataStore.httpCookieStore
        var importedCount = 0

        for (index, entry) in cookieList.enumerated() {
            guard let name = entry["name"] as? String,
                  let value = entry["value"] as? String,
                  let domain = entry["domain"] as? String,
                  let cookiePath = entry["path"] as? String else {
                throw AgentSafariError.cookieFileInvalid("Cookie at index \(index) is missing required fields (name, value, domain, path)")
            }

            var props: [HTTPCookiePropertyKey: Any] = [
                .name: name,
                .value: value,
                .domain: domain,
                .path: cookiePath,
            ]

            if let expiresEpoch = entry["expiresEpoch"] as? Double {
                props[.expires] = Date(timeIntervalSince1970: expiresEpoch)
            }
            if let secure = entry["secure"] as? Bool, secure {
                props[.secure] = "TRUE"
            }
            // HTTPCookiePropertyKey has no public httpOnly key; set via init and
            // the WKHTTPCookieStore will preserve the flag from the cookie object.
            // Build from properties and rely on sameSite via HTTPCookiePropertyKey.sameSitePolicy.
            var sameSiteStr: String? = nil
            if let sameSite = entry["sameSite"] as? String {
                sameSiteStr = sameSite
            }
            if let sameSite = sameSiteStr {
                let policyKey = HTTPCookiePropertyKey("SameSitePolicy")
                switch sameSite.lowercased() {
                case "lax": props[policyKey] = "lax"
                case "strict": props[policyKey] = "strict"
                default: break
                }
            }

            guard let cookie = HTTPCookie(properties: props) else {
                throw AgentSafariError.cookieFileInvalid("Failed to construct HTTPCookie for entry at index \(index) (name=\(name))")
            }

            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                store.setCookie(cookie) {
                    cont.resume()
                }
            }
            importedCount += 1
        }

        return ["path": url.path, "count": String(importedCount)]
    }
}
