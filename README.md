# SmartChat

**Independent chat and social interface AddOn for World of Warcraft: Forever.**

SmartChat combines a customizable tabbed chat interface with an integrated Social Hub, local player journal tools, notifications, and an optional animated Network Map.

> SmartChat is an independent community project. It is not affiliated with, endorsed by, or sponsored by Blizzard Entertainment.

## Target client

- **Game:** World of Warcraft: Forever / Camelot
- **Interface:** 16001
- **Current source package:** 0.7.41 — Animated Optional Network Map

This package targets WoW: Forever. Do not assume compatibility with Retail or other Classic clients unless a release explicitly says so.

## Features

- Customizable chat tabs, filters, unread counters, and a unified Whisper view.
- Global chat view that brings configured chat channels together without changing the actual message destination.
- Social Hub for Friends, Guild, Group, Battle.net contacts, favorites, personal groups, and recent contacts.
- Local Player Journal, notes, contact history, and social summaries.
- Optional Network Map with Node Graph, Radial, and Mind Map layouts. **It is disabled by default** and only builds its visual elements after the player explicitly enables it.
- Per-tab notification sounds, a bundled sound pack, master and per-tab volume controls, and mute controls.
- Chat text appearance controls, including font size from 8 to 48 and available client fonts.
- Keyboard shortcut editor, local backup and restore, and group templates.

Some information depends on fields and APIs exposed by the installed game client. Missing data is not fabricated.

## Installation

1. Close the game client.
2. Download the SmartChat release package.
3. Extract the archive.
4. Copy the **SmartChat** folder into the game's `Interface/AddOns/` directory.
5. Start the game and enable SmartChat in the AddOns list.

Do not place the repository's outer folder inside `AddOns`; the folder containing `SmartChat.toc` must be named `SmartChat`.

## Network Map privacy and performance

Network Map is opt-in and disabled by default. It uses contact and local journal data already available to SmartChat. It does not add a remote network service or a new background polling system. Disabling the map stops its visual effects and clears its rendered objects while preserving source contact and journal data.

## Project status

Version 0.7.41 has passed static source/package checks, but the complete release still requires verification in the live WoW: Forever client. In-game rendering, actual audio playback, client API behavior, and frame-time impact must be tested on the target client.

## Copyright and permissions

Copyright © 2026 Arowtor. All rights reserved.

The SmartChat source code and project materials are publicly visible for inspection. **No general license is granted** to copy, modify, redistribute, sublicense, or commercially exploit the project. Any permissions beyond the limited rights GitHub provides for hosting, viewing, and forking require prior written permission from the copyright holder.

Third-party components and assets, if any, remain subject to their own respective rights and notices. See [ASSET-CREDITS.md](ASSET-CREDITS.md) and [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

## Support and feedback

Please use the GitHub Issues area to report reproducible bugs and compatibility problems. Include the game client/build, SmartChat version, steps to reproduce, and any relevant error text. Do not include private account information.

## Trademarks

World of Warcraft and Blizzard Entertainment are trademarks or registered trademarks of Blizzard Entertainment, Inc. SmartChat is an independent add-on project and is not an official Blizzard product.
