import AppKit
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var overlay: OverlayController?
    var statusItem: NSStatusItem?
    let spotify = SpotifyBridge()

    func applicationDidFinishLaunching(_ notification: Notification) {

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem?.button {
            btn.title = "ᗢ"
            btn.toolTip = "KittyPlayer"
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Player", action: #selector(showPlayer), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "Hide Player", action: #selector(hidePlayer), keyEquivalent: "h"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Connect Spotify…", action: #selector(connectSpotify), keyEquivalent: "l"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit KittyPlayer", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu

        overlay = OverlayController(spotify: spotify)
        overlay?.show()

        spotify.ensureToken { [weak self] ok in
            DispatchQueue.main.async {
                self?.overlay?.sendAuthStatus(connected: ok)
                if ok {
                    self?.spotify.fetchPlaylists { list in
                        self?.overlay?.sendPlaylists(list)
                    }
                }
            }
        }

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.spotify.pollState { state in
                self?.overlay?.sendSpotifyData(state)
            }
        }
    }

    @objc func showPlayer() { overlay?.show() }
    @objc func hidePlayer() { overlay?.hide() }
    @objc func connectSpotify() {
        spotify.login { [weak self] ok in
            DispatchQueue.main.async {
                self?.overlay?.sendAuthStatus(connected: ok)
                if ok {
                    self?.spotify.fetchPlaylists { list in
                        self?.overlay?.sendPlaylists(list)
                    }
                }
            }
        }
    }
    @objc func quit() {
        overlay?.close()
        NSApp.terminate(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
