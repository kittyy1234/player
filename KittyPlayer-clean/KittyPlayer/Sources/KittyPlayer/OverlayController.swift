import AppKit
import WebKit

final class OverlayController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var panel: NSPanel!
    private var webView: WKWebView!
    private let spotify: SpotifyConnector
    private var isReady = false

    init(spotify: SpotifyConnector) {
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
        panel.isMovableByWindowBackground = true

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "kitty")
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

        let candidates: [URL?] = [
            Bundle.main.url(forResource: "overlay", withExtension: "html"),
            Bundle.main.resourceURL?.appendingPathComponent("overlay.html"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/overlay.html"),
        ]
        if let url = candidates.compactMap({ $0 }).first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            let html = "<html><body style='background:transparent;color:#fff;font-family:sans-serif;padding:20px'>KittyPlayer: overlay.html missing from app bundle.</body></html>"
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func show() { panel.orderFrontRegardless() }
    func hide() { panel.orderOut(nil) }
    func close() { panel.close() }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "kitty",
              let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }
        let value = body["value"]

        switch action {
        case "start-drag":
            // Move the panel – WKWebView ignores CSS -webkit-app-region:drag
            if let event = NSApp.currentEvent {
                panel.performDrag(with: event)
            }
        case "resize-window":
            if let dict = value as? [String: Any] {
                let w = (dict["width"] as? NSNumber)?.doubleValue ?? (dict["width"] as? Double) ?? 480
                let h = (dict["height"] as? NSNumber)?.doubleValue ?? (dict["height"] as? Double) ?? 130
                resize(to: CGSize(width: w, height: h))
            }
        case "playpause": spotify.control("playpause")
        case "next": spotify.control("next")
        case "prev": spotify.control("prev")
        case "scrub":
            if let sec = value as? Double ?? (value as? NSNumber)?.doubleValue { spotify.scrub(sec) }
        case "volume":
            if let v = value as? Double ?? (value as? NSNumber)?.doubleValue { spotify.setVolume(v) }
        case "playUri", "playPlaylist":
            if let uri = value as? String { spotify.play(uri: uri) }
        case "getRealPlaylists":
            spotify.fetchPlaylists { [weak self] list in self?.sendPlaylists(list) }
        case "getPlaylistTracks":
            if let id = value as? String {
                spotify.fetchPlaylistTracks(id) { [weak self] tracks in self?.sendTracks(tracks) }
            }
        case "search":
            if let q = value as? String {
                spotify.search(q) { [weak self] tracks in self?.sendSearch(tracks) }
            }
        case "login":
            spotify.login { [weak self] ok in
                self?.sendAuthStatus(connected: ok)
                if ok {
                    self?.spotify.fetchPlaylists { list in self?.sendPlaylists(list) }
                }
            }
        default: break
        }
    }

    private func resize(to size: CGSize) {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        let w = max(320, size.width)
        let h = max(110, size.height)
        var frame = panel.frame
        // Keep bottom-center-ish but allow user position: only change size, keep x/y if already placed
        let x = frame.origin.x
        let y = screen.minY + 20
        // If first resize from default, center; else keep x
        if abs(frame.width - 480) < 2 {
            panel.setFrame(NSRect(x: screen.midX - w / 2, y: y, width: w, height: h), display: true, animate: false)
        } else {
            panel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true, animate: false)
        }
    }

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
        // Inject drag helper in case HTML is old
        let dragJS = """
        (function(){
          if (window.__kittyDragInstalled) return;
          window.__kittyDragInstalled = true;
          function isNoDrag(el) {
            while (el && el !== document.body) {
              if (el.classList && (
                el.classList.contains('btns') ||
                el.classList.contains('vol-container') ||
                el.classList.contains('vol-icon') ||
                el.classList.contains('vol-bg') ||
                el.classList.contains('progress-wrap') ||
                el.classList.contains('bar-bg') ||
                el.classList.contains('art-wrapper') ||
                el.classList.contains('island-waves') ||
                el.classList.contains('drawer') ||
                el.classList.contains('login-btn') ||
                el.classList.contains('list-item') ||
                el.classList.contains('tab') ||
                el.classList.contains('search-box') ||
                el.classList.contains('play-btn') ||
                el.classList.contains('back-btn')
              )) return true;
              if (el.id === 'btnPP' || el.id === 'btnPrev' || el.id === 'btnNext') return true;
              el = el.parentElement;
            }
            return false;
          }
          document.addEventListener('mousedown', function(e) {
            if (e.button !== 0) return;
            if (isNoDrag(e.target)) return;
            try {
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.kitty) {
                window.webkit.messageHandlers.kitty.postMessage({ action: 'start-drag' });
              }
            } catch (err) {}
          }, true);
        })();
        """
        webView.evaluateJavaScript(dragJS, completionHandler: nil)
    }
}
