# KittyPlayer (native)

Native macOS music overlay — **no Electron**.

- Transparent always-on-top player with cat ears
- Spotify playlists / search / playback
- Web API playback so focus stays in Roblox (etc.)
- Universal binary (Apple Silicon + Intel)
- Produces `KittyPlayer.app` + `KittyPlayer.dmg`

## Build on your Mac

```bash
cd KittyPlayer
chmod +x build.sh
./build.sh
```

Outputs:
- `build/KittyPlayer.app`
- `build/KittyPlayer.dmg`

## Install

```bash
# from repo root
chmod +x install.sh
./install.sh
```

Or open the DMG and drag **KittyPlayer** into Applications.

## Usage

1. Open **KittyPlayer** (Spotlight or Applications)
2. Player overlay appears at the bottom of the screen
3. Menu bar **ᗢ** → Connect Spotify…
4. Click the waves on the player to open playlists
5. Quit from the menu bar → player closes

## Requirements

- macOS 12+
- Xcode Command Line Tools (`xcode-select --install`)
- Spotify desktop app (can stay in background)
- Spotify app redirect URI: `http://127.0.0.1:8888/callback`
