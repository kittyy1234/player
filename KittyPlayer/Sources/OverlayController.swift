import AppKit
import WebKit

final class OverlayController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var panel: NSPanel!
    private var webView: WKWebView!
    private let spotify: SpotifyBridge
    private var isReady = false

    init(spotify: SpotifyBridge) {
        self.spotify = spotify
        super.init()
        buildPanel()
    }

    private func buildPanel() {
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let width: CGFloat = 480
        let height: CGFloat = 130
        let x = screen.midX - width / 2
        let y = screen.minY + 20

        panel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        // Critical: do not activate the app when interacting
        panel.isMovableByWindowBackground = true

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "kitty")
        // Transparent page
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        webView = WKWebView(frame: panel.contentView!.bounds, configuration: config)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsBackForwardNavigationGestures = false
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        webView.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(webView)

        // Load bundled overlay.html from app Resources
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "overlay", withExtension: "html"),
            Bundle.main.resourceURL?.appendingPathComponent("overlay.html"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/overlay.html"),
        ]
        if let url = candidates.compactMap({ $0 }).first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            // Fallback: show a tiny error page so we know the resource is missing
            let html = "<html><body style='background:transparent;color:#fff;font-family:sans-serif;padding:20px'>KittyPlayer: overlay.html not found in app bundle.</body></html>"
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func close() {
        panel.close()
    }

    // MARK: - JS → Swift

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "kitty",
              let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        let value = body["value"]

        switch action {
        case "resize-window":
            if let dict = value as? [String: Any] {
                let w = (dict["width"] as? NSNumber)?.doubleValue ?? (dict["width"] as? Double) ?? 480
                let h = (dict["height"] as? NSNumber)?.doubleValue ?? (dict["height"] as? Double) ?? 130
                resize(to: CGSize(width: w, height: h))
            }

        case "playpause":
            spotify.control("playpause")
        case "next":
            spotify.control("next")
        case "prev":
            spotify.control("prev")
        case "scrub":
            if let sec = value as? Double ?? (value as? NSNumber)?.doubleValue {
                spotify.scrub(sec)
            }
        case "volume":
            if let v = value as? Double ?? (value as? NSNumber)?.doubleValue {
                spotify.setVolume(v)
            }
        case "playUri", "playPlaylist":
            if let uri = value as? String {
                // Web API first → no focus steal
                spotify.play(uri: uri)
            }
        case "getRealPlaylists":
            spotify.fetchPlaylists { [weak self] list in
                self?.sendPlaylists(list)
            }
        case "getPlaylistTracks":
            if let id = value as? String {
                spotify.fetchPlaylistTracks(id) { [weak self] tracks in
                    self?.sendTracks(tracks)
                }
            }
        case "search":
            if let q = value as? String {
                spotify.search(q) { [weak self] tracks in
                    self?.sendSearch(tracks)
                }
            }
        case "login":
            spotify.login { [weak self] ok in
                self?.sendAuthStatus(connected: ok)
                if ok {
                    self?.spotify.fetchPlaylists { list in
                        self?.sendPlaylists(list)
                    }
                }
            }
        default:
            break
        }
    }

    private func resize(to size: CGSize) {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        let w = max(320, size.width)
        let h = max(110, size.height)
        let x = screen.midX - w / 2
        let y = screen.minY + 20
        panel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true, animate: false)
    }

    // MARK: - Swift → JS

    private func eval(_ js: String) {
        DispatchQueue.main.async { [weak self] in
            self?.webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    func sendSpotifyData(_ state: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: state),
              let json = String(data: data, encoding: .utf8) else { return }
        eval("window.__kittyRecv && window.__kittyRecv('spotify-data', \(json));")
    }

    func sendPlaylists(_ list: [[String: Any]]) {
        guard let data = try? JSONSerialization.data(withJSONObject: list),
              let json = String(data: data, encoding: .utf8) else { return }
        eval("window.__kittyRecv && window.__kittyRecv('playlists-reply', \(json));")
    }

    func sendTracks(_ list: [[String: Any]]) {
        guard let data = try? JSONSerialization.data(withJSONObject: list),
              let json = String(data: data, encoding: .utf8) else { return }
        eval("window.__kittyRecv && window.__kittyRecv('tracks-reply', \(json));")
    }

    func sendSearch(_ list: [[String: Any]]) {
        guard let data = try? JSONSerialization.data(withJSONObject: list),
              let json = String(data: data, encoding: .utf8) else { return }
        eval("window.__kittyRecv && window.__kittyRecv('search-reply', \(json));")
    }

    func sendAuthStatus(connected: Bool) {
        eval("window.__kittyRecv && window.__kittyRecv('auth-status', {\"connected\": \(connected ? "true" : "false")});")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isReady = true
    }
}
