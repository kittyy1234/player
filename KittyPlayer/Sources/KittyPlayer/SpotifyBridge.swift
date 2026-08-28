
import Foundation
import AppKit
import CryptoKit
import Darwin

final class SpotifyBridge {
    private let clientId = "4119f479e60d4a049e3d384ec366dc65"
    private let redirectURI = "http://127.0.0.1:8888/callback"
    private let scopes = [
        "playlist-read-private",
        "playlist-read-collaborative",
        "user-library-read",
        "user-read-email",
        "user-read-private",
        "user-modify-playback-state",
        "user-read-playback-state",
        "user-read-currently-playing",
    ].joined(separator: " ")

    private var accessToken: String?
    private var tokenExpires: Date = .distantPast
    private var refreshToken: String?
    private var authServer: AuthServer?

    private var tokenURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("KittyPlayer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("token.json")
    }

    init() {
        loadTokens()
    }

    // MARK: - Token storage

    private func loadTokens() {
        guard let data = try? Data(contentsOf: tokenURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        refreshToken = obj["refresh_token"] as? String
        accessToken = obj["access_token"] as? String
        if let exp = obj["expires_at"] as? TimeInterval {
            tokenExpires = Date(timeIntervalSince1970: exp)
        }
    }

    private func saveTokens() {
        var obj: [String: Any] = [:]
        if let r = refreshToken { obj["refresh_token"] = r }
        if let a = accessToken { obj["access_token"] = a }
        obj["expires_at"] = tokenExpires.timeIntervalSince1970
        if let data = try? JSONSerialization.data(withJSONObject: obj) {
            try? data.write(to: tokenURL)
        }
    }

    // MARK: - Auth

    func ensureToken(completion: @escaping (Bool) -> Void) {
        getValidAccessToken { token in
            completion(token != nil)
        }
    }

    func login(completion: @escaping (Bool) -> Void) {
        let verifier = Self.randomString(64)
        let challenge = Self.sha256Base64URL(verifier)
        authServer = AuthServer(port: 8888) { [weak self] code in
            self?.exchangeCode(code, verifier: verifier) { ok in
                completion(ok)
            }
        }
        authServer?.start()

        var comps = URLComponents(string: "https://accounts.spotify.com/authorize")!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        if let url = comps.url {
            NSWorkspace.shared.open(url)
        }
    }

    private func exchangeCode(_ code: String, verifier: String, completion: @escaping (Bool) -> Void) {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientId,
            "code_verifier": verifier,
        ]
        req.httpBody = body.queryString.data(using: .utf8)

        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self, let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let access = obj["access_token"] as? String else {
                completion(false)
                return
            }
            self.accessToken = access
            if let refresh = obj["refresh_token"] as? String {
                self.refreshToken = refresh
            }
            let expiresIn = obj["expires_in"] as? Double ?? 3600
            self.tokenExpires = Date().addingTimeInterval(expiresIn - 30)
            self.saveTokens()
            completion(true)
        }.resume()
    }

    private func getValidAccessToken(completion: @escaping (String?) -> Void) {
        if let t = accessToken, Date() < tokenExpires {
            completion(t)
            return
        }
        guard let refresh = refreshToken else {
            completion(nil)
            return
        }
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": clientId,
        ]
        req.httpBody = body.queryString.data(using: .utf8)
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self, let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let access = obj["access_token"] as? String else {
                completion(nil)
                return
            }
            self.accessToken = access
            if let newRefresh = obj["refresh_token"] as? String {
                self.refreshToken = newRefresh
            }
            let expiresIn = obj["expires_in"] as? Double ?? 3600
            self.tokenExpires = Date().addingTimeInterval(expiresIn - 30)
            self.saveTokens()
            completion(access)
        }.resume()
    }

    // MARK: - API helpers

    private func apiGet(_ path: String, completion: @escaping ([String: Any]?) -> Void) {
        getValidAccessToken { token in
            guard let token else { completion(nil); return }
            var req = URLRequest(url: URL(string: "https://api.spotify.com/v1\(path)")!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            URLSession.shared.dataTask(with: req) { data, response, _ in
                guard let data,
                      let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(nil)
                    return
                }
                completion(obj)
            }.resume()
        }
    }

    private func apiPut(_ path: String, json: [String: Any]?, completion: @escaping (Int) -> Void) {
        getValidAccessToken { token in
            guard let token else { completion(401); return }
            var req = URLRequest(url: URL(string: "https://api.spotify.com/v1\(path)")!)
            req.httpMethod = "PUT"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let json, let body = try? JSONSerialization.data(withJSONObject: json) {
                req.httpBody = body
            }
            URLSession.shared.dataTask(with: req) { _, response, _ in
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                completion(code)
            }.resume()
        }
    }

    // MARK: - Playlists / search

    func fetchPlaylists(completion: @escaping ([[String: Any]]) -> Void) {
        var all: [[String: Any]] = []
        func page(_ path: String) {
            apiGet(path) { obj in
                guard let obj, let items = obj["items"] as? [[String: Any]] else {
                    DispatchQueue.main.async { completion(all) }
                    return
                }
                for p in items {
                    let images = p["images"] as? [[String: Any]]
                    let tracks = p["tracks"] as? [String: Any]
                    let total = tracks?["total"] as? Int
                    var entry: [String: Any] = [
                        "title": p["name"] as? String ?? "Untitled",
                        "id": p["uri"] as? String ?? "",
                        "isPlaylist": true,
                        "artist": total != nil ? "\(total!) tracks" : "",
                    ]
                    if let url = images?.first?["url"] as? String {
                        entry["image"] = url
                    }
                    all.append(entry)
                }
                if let next = obj["next"] as? String,
                   let range = next.range(of: "/v1") {
                    let nextPath = String(next[range.upperBound...])
                    page(nextPath)
                } else {
                    DispatchQueue.main.async { completion(all) }
                }
            }
        }
        page("/me/playlists?limit=50")
    }

    func fetchPlaylistTracks(_ uriOrId: String, completion: @escaping ([[String: Any]]) -> Void) {
        var id = uriOrId
        if id.contains(":") { id = id.split(separator: ":").last.map(String.init) ?? id }
        var all: [[String: Any]] = []
        func page(_ path: String) {
            apiGet(path) { obj in
                guard let obj, let items = obj["items"] as? [[String: Any]] else {
                    DispatchQueue.main.async { completion(all) }
                    return
                }
                for item in items {
                    guard let t = item["track"] as? [String: Any] else { continue }
                    let artists = (t["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.joined(separator: ", ") ?? ""
                    let album = t["album"] as? [String: Any]
                    let images = album?["images"] as? [[String: Any]]
                    var entry: [String: Any] = [
                        "title": t["name"] as? String ?? "",
                        "artist": artists,
                        "id": t["uri"] as? String ?? "",
                    ]
                    if let url = images?.first?["url"] as? String {
                        entry["image"] = url
                    }
                    all.append(entry)
                }
                if let next = obj["next"] as? String,
                   let range = next.range(of: "/v1") {
                    page(String(next[range.upperBound...]))
                } else {
                    DispatchQueue.main.async { completion(all) }
                }
            }
        }
        page("/playlists/\(id)/tracks?limit=100")
    }

    func search(_ query: String, completion: @escaping ([[String: Any]]) -> Void) {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        apiGet("/search?q=\(q)&type=track&limit=20") { obj in
            var list: [[String: Any]] = []
            if let tracks = (obj?["tracks"] as? [String: Any])?["items"] as? [[String: Any]] {
                for t in tracks {
                    let artists = (t["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.joined(separator: ", ") ?? ""
                    let album = t["album"] as? [String: Any]
                    let images = album?["images"] as? [[String: Any]]
                    var entry: [String: Any] = [
                        "title": t["name"] as? String ?? "",
                        "artist": artists,
                        "id": t["uri"] as? String ?? "",
                    ]
                    if let url = images?.first?["url"] as? String {
                        entry["image"] = url
                    }
                    list.append(entry)
                }
            }
            DispatchQueue.main.async { completion(list) }
        }
    }

    // MARK: - Playback (NO FOCUS STEAL)

    /// Prefer Web API so Spotify window is not activated (Roblox stays focused).
    func play(uri: String) {
        let body: [String: Any]
        if uri.contains(":playlist:") || uri.contains(":album:") {
            body = ["context_uri": uri]
        } else {
            body = ["uris": [uri]]
        }
        apiPut("/me/player/play", json: body) { [weak self] status in
            if status == 204 || status == 200 { return }
            // No active device → quietly launch Spotify then retry
            if status == 404 {
                self?.runAppleScript("tell application \"Spotify\" to launch")
                DispatchQueue.global().asyncAfter(deadline: .now() + 1.2) {
                    self?.apiPut("/me/player/play", json: body) { status2 in
                        if status2 == 204 || status2 == 200 { return }
                        // Last resort: AppleScript play + restore front app
                        self?.playQuietAppleScript(uri)
                    }
                }
            } else {
                self?.playQuietAppleScript(uri)
            }
        }
    }

    private func playQuietAppleScript(_ uri: String) {
        let script = """
        tell application "System Events"
          set frontApp to name of first application process whose frontmost is true
        end tell
        tell application "Spotify"
          play track "\(uri)"
        end tell
        delay 0.1
        tell application "System Events"
          try
            set frontmost of process frontApp to true
          end try
        end tell
        delay 0.15
        tell application "System Events"
          try
            set frontmost of process frontApp to true
          end try
        end tell
        """
        runAppleScript(script)
    }

    func control(_ action: String) {
        let cmd: String
        switch action {
        case "playpause": cmd = "tell application \"Spotify\" to playpause"
        case "next": cmd = "tell application \"Spotify\" to next track"
        case "prev": cmd = "tell application \"Spotify\" to previous track"
        default: return
        }
        // Use System Events restore so we don't stick on Spotify
        let script = """
        tell application "System Events"
          set frontApp to name of first application process whose frontmost is true
        end tell
        \(cmd)
        delay 0.08
        tell application "System Events"
          try
            set frontmost of process frontApp to true
          end try
        end tell
        """
        runAppleScript(script)
    }

    func scrub(_ seconds: Double) {
        runAppleScript("tell application \"Spotify\" to set player position to \(Int(seconds))")
    }

    func setVolume(_ v: Double) {
        let vol = max(0, min(100, Int((v * 100).rounded())))
        runAppleScript("tell application \"Spotify\" to set sound volume to \(vol)")
    }

    // MARK: - Poll state via AppleScript (lightweight)

    func pollState(completion: @escaping ([String: Any]) -> Void) {
        let script = """
        if application "Spotify" is running then
          tell application "Spotify"
            try
              set cTrack to current track
              set trackName to name of cTrack
              set artistName to artist of cTrack
              set totalDur to duration of cTrack
              set playerPos to player position
              set pState to player state as string
              set artworkUrl to artwork url of cTrack
              set trackId to id of cTrack
              set curVol to sound volume
              return trackName & "||" & artistName & "||" & totalDur & "||" & playerPos & "||" & pState & "||" & artworkUrl & "||" & trackId & "||" & curVol
            on error
              return "No Track"
            end try
          end tell
        end if
        return "No Track"
        """
        DispatchQueue.global(qos: .utility).async {
            var error: NSDictionary?
            let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
            let stdout = result?.stringValue ?? "No Track"
            if stdout == "No Track" {
                DispatchQueue.main.async {
                    completion([
                        "track": "KittyPlayer",
                        "artist": "No track playing",
                        "position": 0,
                        "duration": 1,
                        "status": "paused",
                        "image": "",
                        "id": "",
                    ])
                }
                return
            }
            let parts = stdout.components(separatedBy: "||")
            guard parts.count >= 7 else { return }
            let trackTitle = parts[0]
            let artistName = parts[1]
            let rawDur = Double(parts[2]) ?? 0
            let rawPos = Double(parts[3]) ?? 0
            let isAd = trackTitle.lowercased().contains("advertisement")
                || artistName.lowercased().contains("spotify")
                || rawDur == 0
            let duration = isAd ? 30.0 : floor(rawDur / 1000)
            let position = isAd ? floor(rawPos) : rawPos
            let volume = parts.count > 7 ? max(0, min(1, (Double(parts[7]) ?? 70) / 100)) : 0.7

            if isAd && parts[4].lowercased() == "playing" {
                self.runAppleScript("tell application \"Spotify\" to next track")
            }

            var state: [String: Any] = [
                "track": trackTitle,
                "artist": artistName,
                "duration": duration,
                "position": position,
                "status": parts[4].lowercased(),
                "image": parts[5],
                "id": parts[6],
                "isAd": isAd,
                "volume": volume,
            ]
            DispatchQueue.main.async { completion(state) }
        }
    }

    // MARK: - Helpers

    private func runAppleScript(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
        }
    }

    private static func randomString(_ length: Int) -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    private static func sha256Base64URL(_ input: String) -> String {
        let data = Data(input.utf8)
        let digest = SHA256.hash(data: data)
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension Dictionary where Key == String, Value == String {
    var queryString: String {
        map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
    }
}

/// Tiny localhost callback server for Spotify PKCE
final class AuthServer {
    private let port: UInt16
    private var socket: Int32 = -1
    private let onCode: (String) -> Void
    private var source: DispatchSourceRead?

    init(port: UInt16, onCode: @escaping (String) -> Void) {
        self.port = port
        self.onCode = onCode
    }

    func start() {
        DispatchQueue.global().async { [weak self] in
            self?.serve()
        }
    }

     private func serve() {
        let sock = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return }
        var reuse: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout.size(ofValue: reuse)))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { close(sock); return }
        listen(sock, 1)

        var clientAddr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let client = withUnsafeMutablePointer(to: &clientAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                accept(sock, $0, &len)
            }
        }
        guard client >= 0 else { close(sock); return }

        var buffer = [UInt8](repeating: 0, count: 8192)
        let n = read(client, &buffer, buffer.count)
        let request = n > 0 ? String(bytes: buffer[0..<n], encoding: .utf8) ?? "" : ""

        var code = ""
        if let range = request.range(of: "GET /callback?code=") {
            let rest = request[range.upperBound...]
            code = String(rest.prefix(while: { (ch: Character) -> Bool in ch != " " && ch != "&" }))
        } else if let r = request.range(of: "code=") {
            let rest = request[r.upperBound...]
            code = String(rest.prefix(while: { (ch: Character) -> Bool in
                ch != " " && ch != "&" && ch != "\r" && ch != "\n"
            }))
        }

        let html = "<html><body style='font-family:sans-serif;padding:40px'><h2>Connected ✓</h2><p>You can close this tab and return to KittyPlayer.</p></body></html>"
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
        _ = response.withCString { write(client, $0, strlen($0)) }
        close(client)
        close(sock)

        if !code.isEmpty {
            DispatchQueue.main.async { self.onCode(code) }
        }
    }
