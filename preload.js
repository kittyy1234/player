const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('electronAPI', {
  resizeWindow: (bounds) => ipcRenderer.send('resize-window', bounds),
  sendControl: (action, value) => ipcRenderer.send('spotify-control', { action, value }),
  onSpotifyData: (cb) => ipcRenderer.on('spotify-data', (_, data) => cb(data)),
  onPlaylistsReply: (cb) => ipcRenderer.on('playlists-reply', (_, data) => cb(data)),
  onTracksReply: (cb) => ipcRenderer.on('tracks-reply', (_, data) => cb(data)),
  onSearchReply: (cb) => ipcRenderer.on('search-reply', (_, data) => cb(data)),
});
