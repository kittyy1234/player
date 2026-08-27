const { app, BrowserWindow, screen, ipcMain, Tray, Menu, nativeImage } = require('electron');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');
const http = require('http');
const { exec } = require('child_process');
const fetch = require('node-fetch');
const CLIENT_ID = "4119f479e60d4a049e3d384ec366dc65";
const REDIRECT_URI = "http://127.0.0.1:8888/callback";
// Extra scopes so we can start playback via Web API (no focus steal) + read playlists
const SCOPES = [
  "playlist-read-private",
  "playlist-read-collaborative",
  "user-library-read",
  "user-read-email",
  "user-read-private",
  "user-modify-playback-state",
  "user-read-playback-state",
  "user-read-currently-playing",
].join(" ");
const TOKEN_PATH = path.join(app.getPath('userData'), 'token.json');
const PLAYLISTS_PATH = path.join(app.getPath('userData'), 'playlists.json');
let win;
let tray = null;
let accessToken = null;
let tokenExpires = 0;
function base64url(buf) {
  return buf.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}
function loadTokens() {
  try { return JSON.parse(fs.readFileSync(TOKEN_PATH, 'utf8')); } catch (e) { return null; }
}
function saveTokens(tokens) {
  fs.writeFileSync(TOKEN_PATH, JSON.stringify(tokens));
}
async function exchangeCode(code, verifier) {
  const res = await fetch('https://accounts.spotify.com/api/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'authorization_code', code, redirect_uri: REDIRECT_URI,
      client_id: CLIENT_ID, code_verifier: verifier,
    }),
  });
  return res.json();
}
async function refreshTokens(refreshToken) {
  const res = await fetch('https://accounts.spotify.com/api/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'refresh_token', refresh_token: refreshToken, client_id: CLIENT_ID,
    }),
  });
  return res.json();
}
function runLoginFlow() {
  return new Promise((resolve, reject) => {
    const verifier = base64url(crypto.randomBytes(64));
    const challenge = base64url(crypto.createHash('sha256').update(verifier).digest());
    const server = http.createServer(async (req, res) => {
      const url = new URL(req.url, REDIRECT_URI);
      const code = url.searchParams.get('code');
      if (!code) { res.end('Missing code'); return; }
      res.end('<html><body style="font-family:sans-serif;padding:40px"><h2>Connected. You can close this tab.</h2></body></html>');
      server.close();
      try {
        const data = await exchangeCode(code, verifier);
        if (!data.refresh_token) { reject(new Error(JSON.stringify(data))); return; }
        saveTokens({ refresh_token: data.refresh_token });
        accessToken = data.access_token;
        tokenExpires = Date.now() + (data.expires_in - 30) * 1000;
        resolve();
      } catch (e) { reject(e); }
    });
    server.listen(8888, () => {
      const params = new URLSearchParams({
        client_id: CLIENT_ID,
        response_type: 'code',
        redirect_uri: REDIRECT_URI,
        code_challenge_method: 'S256',
        code_challenge: challenge,
        scope: SCOPES,
        // Force consent so new scopes (playback) are granted on reconnect
        prompt: 'consent',
      });
      exec(`open "https://accounts.spotify.com/authorize?${params.toString()}"`);
    });
  });
}
async function getValidAccessToken() {
  if (accessToken && Date.now() < tokenExpires) return accessToken;
  const stored = loadTokens();
  if (!stored || !stored.refresh_token) return null;
  const data = await refreshTokens(stored.refresh_token);
  if (!data.access_token) return null;
  accessToken = data.access_token;
  tokenExpires = Date.now() + (data.expires_in - 30) * 1000;
  if (data.refresh_token) saveTokens({ refresh_token: data.refresh_token });
  return accessToken;
}
async function spotifyGet(endpoint) {
  const token = await getValidAccessToken();
  if (!token) {
    console.log('[KittyPlayer] spotifyGet: no token for', endpoint);
    return null;
  }
  const res = await fetch('https://api.spotify.com/v1' + endpoint, {
    headers: { Authorization: 'Bearer ' + token },
  });
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    console.log('[KittyPlayer] spotifyGet failed', res.status, endpoint, body.slice(0, 200));
    return null;
  }
  return res.json();
}

async function spotifyPut(endpoint, body) {
  const token = await getValidAccessToken();
  if (!token) return { ok: false, status: 401 };
  const res = await fetch('https://api.spotify.com/v1' + endpoint, {
    method: 'PUT',
    headers: {
      Authorization: 'Bearer ' + token,
      'Content-Type': 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { ok: res.ok || res.status === 204, status: res.status };
}
function loadCachedPlaylists() {
  try { return JSON.parse(fs.readFileSync(PLAYLISTS_PATH, 'utf8')); } catch (e) { return null; }
}
function savePlaylists(playlists) {
  fs.writeFileSync(PLAYLISTS_PATH, JSON.stringify(playlists));
}
function sendAuthStatus(connected) {
  if (win && !win.isDestroyed()) {
    win.webContents.send('auth-status', { connected: !!connected });
  }
}
async function fetchAllPlaylists() {
  let all = [];
  let url = '/me/playlists?limit=50';
  let pages = 0;
  while (url && pages < 10) {
    pages++;
    const res = await spotifyGet(url);
    if (!res) {
      console.log('[KittyPlayer] fetchAllPlaylists: null response on page', pages);
      break;
    }
    if (!Array.isArray(res.items)) {
      console.log('[KittyPlayer] fetchAllPlaylists: no items array', JSON.stringify(res).slice(0, 200));
      break;
    }
    all = all.concat(res.items.map((p) => ({
      title: p.name || 'Untitled',
      id: p.uri || p.id,
      isPlaylist: true,
      image: (p.images && p.images[0]) ? p.images[0].url : null,
      artist: (p.tracks && typeof p.tracks.total === 'number') ? `${p.tracks.total} tracks` : '',
    })));
    url = res.next ? res.next.replace('https://api.spotify.com/v1', '') : null;
  }
  console.log('[KittyPlayer] fetchAllPlaylists got', all.length, 'playlists');
  if (all.length > 0) savePlaylists(all);
  return all;
}

/** Start playback via Web API so Spotify window is NOT activated (stays in Roblox etc.) */
async function playViaWebApi(uri) {
  if (!uri) return false;
  // context_uri for playlists/albums, uris[] for single tracks
  let body;
  if (String(uri).includes(':playlist:') || String(uri).includes(':album:')) {
    body = { context_uri: uri };
  } else {
    body = { uris: [uri] };
  }
  let result = await spotifyPut('/me/player/play', body);
  if (result.ok) {
    console.log('[KittyPlayer] Web API play OK');
    return true;
  }
  // 404 = no active device. Quietly launch Spotify (does not bring to front like activate)
  // then retry once after a short delay.
  if (result.status === 404) {
    console.log('[KittyPlayer] No active device – launching Spotify quietly and retrying');
    await new Promise((resolve) => {
      exec(`osascript -e 'tell application "Spotify" to launch'`, () => resolve());
    });
    await new Promise((r) => setTimeout(r, 1200));
    result = await spotifyPut('/me/player/play', body);
    if (result.ok) {
      console.log('[KittyPlayer] Web API play OK after launch');
      return true;
    }
  }
  console.log('[KittyPlayer] Web API play failed status', result.status);
  return false;
}
async function extractDominantColor(imageUrl) {
  if (!imageUrl) return null;
  try {
    const res = await fetch(imageUrl);
    if (!res.ok) return null;
    const buf = await res.buffer();
    const img = nativeImage.createFromBuffer(buf);
    if (img.isEmpty()) return null;
    const size = img.getSize();
    const w = Math.min(16, size.width);
    const h = Math.min(16, size.height);
    const resized = img.resize({ width: w, height: h });
    const png = resized.toPNG();
    let r = 0, g = 0, b = 0, count = 0;
    for (let i = 0; i < png.length - 3; i += 4) {
      const pr = png[i], pg = png[i + 1], pb = png[i + 2];
      const sum = pr + pg + pb;
      if (sum > 40 && sum < 700) { r += pr; g += pg; b += pb; count++; }
    }
    if (count === 0) return null;
    return { r: Math.floor(r / count), g: Math.floor(g / count), b: Math.floor(b / count) };
  } catch (e) { return null; }
}
function playUriQuiet(uri) {
  // Play without stealing focus (keeps Roblox / current app in front)
  // Write script to temp file to avoid shell-quoting issues
  const script = `
tell application "System Events"
  set frontApp to name of first application process whose frontmost is true
end tell
tell application "Spotify"
  play track "${uri}"
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
`;
  const tmp = path.join(app.getPath('temp'), 'kittyplayer-play.scpt');
  fs.writeFileSync(tmp, script);
  exec(`osascript "${tmp}"`, () => {
    try { fs.unlinkSync(tmp); } catch (e) {}
  });
}
function createOverlayWindow() {
  const { width, height } = screen.getPrimaryDisplay().workAreaSize;
  win = new BrowserWindow({
    width: 480, height: 110,
    x: Math.floor((width - 480) / 2), y: height - 130,
    frame: false, transparent: true, alwaysOnTop: true,
    resizable: true, hasShadow: false, skipTaskbar: true,
    webPreferences: {
      nodeIntegration: false, contextIsolation: true,
      preload: path.join(__dirname, 'preload.js'),
    },
  });
  win.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  win.setAlwaysOnTop(true, 'screen-saver', 1);
  win.loadFile(path.join(__dirname, 'overlay.html'));
  startPollingLoop();
}
function createTrayMenu() {
  const iconPath = path.join(__dirname, 'Icon.png');
  const icon = nativeImage.createFromPath(iconPath);
  tray = new Tray(icon);
  const contextMenu = Menu.buildFromTemplate([
    { label: 'Show', click: () => { if (win && !win.isDestroyed()) win.showInactive(); } },
    { label: 'Hide', click: () => { if (win && !win.isDestroyed()) win.hide(); } },
    { type: 'separator' },
    { label: 'Quit', click: () => app.quit() },
  ]);
  tray.setContextMenu(contextMenu);
  tray.setToolTip('KittyPlayer123');
}
function startPollingLoop() {
  setInterval(() => {
    if (!win || win.isDestroyed()) return;
    const script = `
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
    `;
    exec(`osascript -e '${script}'`, async (err, stdout) => {
      if (err || !stdout || stdout.trim() === 'No Track') {
        win.webContents.send('spotify-data', { track: 'KittyPlayer123', artist: 'No track playing', position: 0, duration: 1, status: 'paused', image: '', id: '', color: null });
        return;
      }
      const parts = stdout.trim().split('||');
      if (parts.length >= 7) {
        const trackTitle = parts[0];
        const artistName = parts[1];
        const rawDur = Number(parts[2]);
        const rawPos = Number(parts[3]);
        const isAd = trackTitle.toLowerCase().includes('advertisement') || artistName.toLowerCase().includes('spotify') || rawDur === 0;
        const duration = isAd ? 30 : Math.floor(rawDur / 1000);
        const position = isAd ? Math.floor(rawPos) : rawPos;
        let color = null;
        if (parts[5] && !isAd) color = await extractDominantColor(parts[5]);
        const volume = parts[7] !== undefined ? Math.max(0, Math.min(1, Number(parts[7]) / 100)) : undefined;
        // Lightweight ad skip – jump to next track when Spotify is playing an ad
        if (isAd && parts[4].toLowerCase() === 'playing') {
          exec(`osascript -e 'tell application "Spotify" to next track'`);
        }
        win.webContents.send('spotify-data', {
          track: trackTitle, artist: artistName, duration, position,
          status: parts[4].toLowerCase(), image: parts[5], id: parts[6], isAd, color, volume,
        });
      }
    });
  }, 1000);
}
ipcMain.on('spotify-control', async (event, data) => {
  if (['playpause', 'next', 'prev', 'scrub'].includes(data.action)) {
    let script = '';
    if (data.action === 'playpause') script = 'tell application "Spotify" to playpause';
    if (data.action === 'next') script = 'tell application "Spotify" to next track';
    if (data.action === 'prev') script = 'tell application "Spotify" to previous track';
    if (data.action === 'scrub') script = `tell application "Spotify" to set player position to ${data.value}`;
    if (script) exec(`osascript -e '${script}'`);
    return;
  }
  // Volume control (0.0 – 1.0) → Spotify sound volume 0–100
  if (data.action === 'volume') {
    const vol = Math.max(0, Math.min(100, Math.round(Number(data.value) * 100)));
    const script = `tell application "Spotify" to set sound volume to ${vol}`;
    exec(`osascript -e '${script}'`);
    return;
  }
  // Manual login / reconnect from the drawer button
  if (data.action === 'login') {
    runLoginFlow()
      .then(async () => {
        sendAuthStatus(true);
        try {
          const all = await fetchAllPlaylists();
          if (win && !win.isDestroyed()) win.webContents.send('playlists-reply', all);
        } catch (e) {
          if (win && !win.isDestroyed()) win.webContents.send('playlists-reply', []);
        }
      })
      .catch(() => {
        sendAuthStatus(false);
      });
    return;
  }
  if (data.action === 'playUri' || data.action === 'playPlaylist') {
    // Prefer Web API (no focus steal). Fall back to quiet AppleScript if no active device.
    const uri = data.value;
    playViaWebApi(uri).then((ok) => {
      if (!ok) playUriQuiet(uri);
    });
    return;
  }
  if (data.action === 'getRealPlaylists') {
    const cached = loadCachedPlaylists();
    if (cached && cached.length > 0) win.webContents.send('playlists-reply', cached);
    // Always report whether we think we're logged in
    const token = await getValidAccessToken();
    sendAuthStatus(!!token);
    try {
      const all = await fetchAllPlaylists();
      win.webContents.send('playlists-reply', all.length ? all : (cached || []));
    } catch (e) {
      if (!cached) win.webContents.send('playlists-reply', []);
    }
    return;
  }
  if (data.action === 'getPlaylistTracks') {
    try {
      let playlistId = data.value;
      if (playlistId.includes(':')) playlistId = playlistId.split(':').pop();
      let all = [];
      let url = `/playlists/${playlistId}/tracks?limit=100`;
      while (url) {
        const res = await spotifyGet(url);
        if (!res || !res.items) break;
        all = all.concat(res.items.filter((i) => i.track).map((i) => ({
          title: i.track.name,
          artist: i.track.artists.map((a) => a.name).join(', '),
          id: i.track.uri,
          image: (i.track.album && i.track.album.images && i.track.album.images[0]) ? i.track.album.images[0].url : null,
        })));
        url = res.next ? res.next.replace('https://api.spotify.com/v1', '') : null;
      }
      win.webContents.send('tracks-reply', all);
    } catch (e) {
      win.webContents.send('tracks-reply', []);
    }
    return;
  }
  if (data.action === 'search') {
    try {
      const q = encodeURIComponent(data.value);
      const res = await spotifyGet(`/search?q=${q}&type=track&limit=20`);
      if (!res || !res.tracks) { win.webContents.send('search-reply', []); return; }
      const tracks = res.tracks.items.map((t) => ({
        title: t.name,
        artist: t.artists.map((a) => a.name).join(', '),
        id: t.uri,
        image: (t.album && t.album.images && t.album.images[0]) ? t.album.images[0].url : null,
      }));
      win.webContents.send('search-reply', tracks);
    } catch (e) {
      win.webContents.send('search-reply', []);
    }
    return;
  }
});
ipcMain.on('resize-window', (event, bounds) => {
  if (!win || win.isDestroyed()) return;
  const { width: scrW, height: scrH } = screen.getPrimaryDisplay().workAreaSize;
  win.setBounds({
    width: Math.floor(bounds.width),
    height: Math.floor(bounds.height),
    x: Math.floor((scrW - bounds.width) / 2),
    y: scrH - Math.floor(bounds.height) - 20,
  }, true);
});
app.whenReady().then(async () => {
  const stored = loadTokens();
  if (!stored || !stored.refresh_token) {
    try { await runLoginFlow(); } catch (e) {}
  }
  createOverlayWindow();
  createTrayMenu();
  // After window exists, report auth + try to preload playlists
  setTimeout(async () => {
    const token = await getValidAccessToken();
    sendAuthStatus(!!token);
    if (token) {
      try {
        const all = await fetchAllPlaylists();
        if (win && !win.isDestroyed()) win.webContents.send('playlists-reply', all);
      } catch (e) {}
    }
  }, 800);
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createOverlayWindow();
  });
});
app.on('window-all-closed', () => { app.quit(); });
