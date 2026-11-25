# Third-Party Notices

## SmartChat 0.5.0-beta.1 package audit

The distributable package was checked for bundled dependencies and separate third-party asset files.

- **Code libraries:** No third-party Lua libraries or embedded dependency folders are bundled. The add-on loads its own Lua files through `SmartChat.toc`.
- **Fonts:** No font files are distributed. Font choices refer to fonts already installed by the World of Warcraft client.
- **Game UI assets:** No Blizzard executable, texture, icon, or audio files are copied into the package. The TOC references an icon texture supplied by the player's installed game client.
- **Sound pack:** The 100 OGG files are the 10 custom SmartChat notification sounds with pre-rendered volume levels. The project owner identifies these as original assets created specifically for SmartChat, not Blizzard game recordings or third-party music. See [ASSET-CREDITS.md](ASSET-CREDITS.md).

No separate third-party code or asset notices were identified in the contents of this release package. Any future third-party component or asset must be reviewed for redistribution rights and documented here before it is included.
