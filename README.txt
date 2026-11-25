SmartChat 0.5.0 Beta 1 - Public Beta Release

LOCAL HISTORY AND PRIVACY
  Chat History is disabled by default. When enabled, chat text including Whisper
  text is stored locally in SavedVariables. Users can set the age limit and the
  maximum stored line count in Settings (defaults: 7 days and 1,000 lines).
  The login replay count is separate. Player Journal is also opt-in and stores
  Whisper interaction metadata, not Whisper message content.


Version 0.7.37 additions
- Added reusable Group Templates: save a My Group or a multi-selected contact list as a template, create a new My Group from a saved template, update a template from a current group, invite its character members to your Party, or delete the template.
- Added a Group Templates manager opened from the Groups category right-click menu. Templates are local snapshots; edits to the source My Group do not silently change a saved template.
- Added Invite Available Members to Party for a selected My Group, a saved template, or a multi-selection. The user explicitly confirms batch invitations; offline, account-only, duplicate and already-grouped contacts are skipped, invitations are capped by the remaining slots in a normal five-player Party, and Raid invitations are left to the game's own tools.
- Kept the individual Invite to Party contact action and routed it through the same validation helper.
- Added Group Templates and their member lists to portable Social Backup / Import. Older backup files remain compatible; template data is merged without replacing local groups or notes.
- Group templates are local SmartChat contact lists only. They do not create an in-game group, change Friend/Guild membership, or manage Raid rosters.
- No polling, timers, external network requests or continuous background processing were added. Party invitations occur only after an explicit user action and confirmation for multi-invites.
- Syntax-checked all Lua files and tested template create/copy/update/delete, backup round-trips and Party invite filtering with mocked API data. Not tested inside the live WoW: Forever client.

SmartChat 0.7.38 - World of Warcraft: Forever

Version 0.7.37 - My Groups and Party Companion
- Added six Guild Manager views: Overview, Roster, Level & Class, Rank & Achievements, Activity and Analytics.
- Guild summaries include member presence, level distribution and averages, class and rank composition, Achievement Points and last-online age when supplied by the current client.
- Clickable drill-down filters show matching Guild members in the existing roster list. Search, sort and global contact filters continue to apply.
- Added Achievement Points sorting and selected-member Achievement Points / Guild Achievement Rank details when available.
- Guild data is read from the current Guild Roster and refreshed on roster update; no continuous polling or external network requests are used.
- Missing client fields are shown as unavailable and excluded from statistics.

TARGET CLIENT
  WoW: Forever / Camelot, interface 16001.
  This package is built specifically for Forever. It is not the Retail 11.x/12.x package.

INSTALL
  1. Close World of Warcraft.
  2. Copy the SmartChat folder into:
       World of Warcraft/_forever_/Interface/AddOns/
  3. Confirm that this file exists:
       .../_forever_/Interface/AddOns/SmartChat/SmartChat.toc
  4. Start WoW Forever. If you changed Lua files while the game was open, use /reload.

OPEN SETTINGS
  Type /sc

FEATURES
  - Independent settings pages (Sound, Chat Text, Social & Journal, Backup/Restore and Shortcuts) open above the main Settings window with consistent Back/Close behavior.
  - Chat font size is adjustable from 8 to 48; the optional typing-box font grows its input area when needed and restores the original height when disabled/reset.
  - Tabs for Say, Global, Party, Raid, Guild, General and Whisper. Global is an aggregate read-only view that shows all chat and game messages captured by the main chat window.
  - Messages also appear in Global when they arrive in Say, Party, Raid, Guild, Officer, Whisper, Yell, Emote, Instance or any joined channel. A message is shown once in Global; its original channel tab remains independent.
  - Global unread count is independent. The same incoming message can increase the unread count on both its channel tab and Global when both are inactive, while SmartChat plays at most one notification sound. Your own outgoing messages appear in the relevant tab and Global without unread counts or alert sounds.
  - Global is view-only: selecting it does not change the destination used by the game's chat input. The last real channel selected remains the send destination; on a fresh character the game default is used.
  - Plain web and Discord URLs in visible chat lines become clickable copy links; clicking opens a selected URL field for Ctrl+C. Native WoW hyperlinks are unchanged.
  - A tab can preselect the chat channel before you type. The game edit box sends the
    message normally; SmartChat does not send chat messages by itself.
  - Whisper has exactly one main SmartChat tab. While selected, a compact vertical contact list appears inside the chat window on the left, styled like the existing SmartChat tabs. The selected conversation remains in the normal chat message area on the right and uses the normal chat input; no extra main tabs or floating windows are created.
  - Social Hub remains a separate dock icon and opens its own larger contact workspace. It includes All, Friends, Guild, Group, Whispers, BNet, Favorites, Recent, custom Groups, Journal, Activity and Ignored categories. It shares the same recent Whisper contacts used by the single built-in Whisper tab.
  - Social Hub supports contact search across names and available profile fields, online-only filtering, status/name/recent sorting plus Guild Rank, Level and Class sorting, Favorites, pinned contacts and up to 30 private contact groups. Group membership is local to SmartChat and does not change the game's Friend or Guild lists.
  - Friends Manager supports multi-select across the current visible contact list. Bulk actions can add/remove selected contacts from SmartChat Favorites, Pin/Unpin them, add them to personal groups, remove them from the currently selected custom group, create a new group or reusable Group Template from the selection, and invite selected character contacts to a normal Party after confirmation. These are local SmartChat organization actions except explicit Party invitations; they do not mass-edit the in-game Friend, Guild or Ignore lists.
  - My Groups supports reusable Group Templates. Save a My Group or selected contacts as a snapshot, create a new local group from that template, update or delete a template, and invite its eligible members to a normal Party after explicit confirmation. Templates do not create in-game groups or manage Raid rosters.
  - Social Intelligence adds a dedicated Insights category with local weekly/monthly/all-time summaries, frequent group partners, recurring Whisper contacts, recorded locations and transparent optional Favorite/Pin suggestions. It never modifies contacts automatically.
  - Player Profile includes a Network section showing recorded group partners, current Guild roster connections, your own private-group co-members and currently reported characters on the same Battle.net account when exposed by the client. Mutual friends are not inferred because the game does not expose another player's Friend List.
  - Smart Player Discovery ranks only contacts known through game rosters, Whisper history, custom groups or recorded Journal events. Rankings and recommendations are calculated on demand from the bounded local Journal; they add no polling, network requests or permanent background processing.
  - The Battle.net category keeps account-only friends visible when the client does not expose an active WoW character, including offline or non-WoW accounts when a safe display name is available. Such rows can be favorited, pinned, grouped and annotated, but do not show invalid character-only actions.
  - Battle.net account rows and currently reported game accounts are linked in the live Social Hub cache. Selecting a known WoW character shows its BattleTag/account label, the number of game accounts exposed by the client, other currently reported WoW characters, and available non-WoW game presence. Multiple rows from the same Battle.net account are grouped together by account identity in the default BNet sort.
  - Battle.net game-account details are session-only API data. Temporary account/game-account identifiers are not written to SavedVariables or portable backups. The displayed game accounts are only those exposed by the current client session, not a full roster of every character on the account; offline or hidden characters are never guessed.
  - Guild rows include available rank, class, level and last reported zone. Group rows include role when the game API supplies it.
  - Right-click a contact for quick actions: open Whisper, add/remove Favorite, pin/unpin, add a Quick Note, view the Player Journal, manage custom contact groups, prepare an Add Friend slash command, invite to Party, or Ignore/Unignore when the client exposes the API. Add Friend is prepared in the chat input because the game marks the direct AddFriend API as restricted; press Enter yourself to confirm.
  - Social Hub displays available Class, Level, Guild rank, Zone, BattleTag and presence data. Unavailable values remain unknown rather than being guessed. The Ignored category uses the game's ignore roster when exposed.
  - Optional Network Map is a category inside the existing Social Hub window; it never opens a separate window. It reads an on-demand snapshot from existing Friends, Guild, current Group, Battle.net, Whisper, Favorites, My Groups and recorded Group Journal data. It does not start tracking, polling or network activity of its own.
  - The presentation is intentionally elaborate: layered glowing connection paths, traveling energy pulses, illuminated node halos, twinkling node accents, a subtle animated starfield and staggered node entrances. Choose Node Graph, Radial or Mind Map layouts and Midnight, Neon or Minimal themes; use zoom, pan, relationship filters and contact Profile/Whisper actions.
  - Network Map is OFF by default. Before you press Enable Network Map, no graph canvas, contact nodes, connection lines, decorative starfield or animation groups are created. The first snapshot and visual effects are built only after explicit activation or an on-demand refresh while enabled. Disable stops all effects and clears rendered map content without touching source contacts or Journal data. Animation can be turned off; Reduce Motion suppresses looping and entrance effects.
  - Network Map reads only known relationship data. It does not infer mutual Friends, hidden Battle.net characters, Dungeon completion or unsupported links. Recorded Group Partners depend on Player Journal events that were actually collected while tracking was enabled.
  - Player Journal is an optional, local-only social history module. It is OFF by default and can be enabled in Settings > Social & Journal. It records selected Friend/Guild changes, group sessions and visited instance/zone names, Whisper interaction dates/counts (never message text), and optionally your own Quest turn-ins with the group roster present. Group presence is not treated as proof that every member completed a Quest or Dungeon.
  - Player Journal has a lazy timeline inside Social Hub, ready-made one-click note tags, optional short personal notes, 90-day event retention and a 500-event default cap. Event retention and cap can be adjusted. Notes/tags are preserved when automatic tracking is disabled; up to 500 contact notes are retained. No network requests are used. Events are tracked only from game events; no polling loop is used.
  - Player Journal profiles show per-player summaries for recorded group sessions, actual tracked time spent in each group session, Whisper interaction counts, Friend/Guild relationship changes, first/last recorded interaction and known locations. New group-session attendance accounts for members joining, leaving and rejoining during a session. Older group records are marked as estimated because they did not store individual attendance.
  - Group session records include available instance type, difficulty, instance ID, maximum observed group size, overall session duration, per-player attendance intervals and visited locations. These fields are recorded only when the corresponding game events/APIs supply them; a group session is not treated as proof of dungeon completion.
  - Activity and Player Journal timelines have lazy event-type and time-range filters. Timeline rows show each player's tracked attendance time for new group sessions.
  - Social Intelligence is read-only. It reports recorded co-presence, current Guild membership and your own locally assigned groups as separate evidence types. It does not claim mutual-friend status, objective completion, exact simultaneous presence or personal qualities. Suggestions are optional prompts derived from recorded interaction counts. The Insights dashboard provides 7-day, 30-day, 90-day and all-recorded-history summaries, top contacts, group partners, Whisper contacts, recorded locations and optional Favorite/Pin prompts.
  - Social Data Backup / Restore has separate Export, Import and Local Save pages. Normal in-game use is saved automatically by WoW through SmartChat SavedVariables on logout/reload; Ctrl+C / Ctrl+V is not needed during regular play. Portable Export/Import still uses manual copy/paste because AddOns cannot freely write arbitrary files or access the operating-system clipboard. A single local restore point can be created manually and is also created automatically before a portable import. Restore swaps the current data with the saved point, so the previous state remains available as a swap-back point. Whisper message text, chat history and Battle.net account identifiers are excluded.
  - Social Activity Feed can record known Friend, Guild, Battle.net and Party/Raid presence or roster changes when the matching Player Journal tracking options are enabled. Online/Offline, AFK and DND states are recorded only when the client exposes a known state; Appear Offline and Unknown are never treated as Offline.
  - Optional in-game Social Notifications show small local toast popups for selected Friend, Guild, Group and Battle.net changes. Notifications are OFF by default and are configured separately from Player Journal history. Toasts are event-driven, queued (maximum four waiting) and can be clicked to open Social Hub.
  - Social notification tracking uses game events and in-memory status snapshots. It adds no polling loop, network traffic or background update timer. Player Journal remains OFF by default; presence history and Guild/Group roster history have separate opt-in switches because they can create additional events.
  - Click a tab to show it without opening the typing box by default. The selected channel is applied immediately to the edit box the game will actually use for sending (including last-active/docked chat windows in IM chat style), even while it is hidden. Press Enter or click the game's input box to type in the selected channel. The old auto-focus behavior can be enabled in /sc settings.
  - Drag and drop tabs to reorder them. Hold the left mouse button on a tab and move it horizontally along the tab strip. The tab stays locked to that row; releasing outside the strip cancels the drag. SmartChat inserts it at the nearest horizontal position and saves the order. Right-click a tab for its settings; middle-click keeps the alternate reorder menu.
  - A vertical icon dock on the LEFT side of chat opens the channel selector, Social Hub, settings, keyboard shortcuts, copy window and new-tab window. Toggle it with /sc dock or in settings.
  - Open the shortcut editor from the Keyboard shortcuts button inside Settings or the clearly drawn keyboard icon in the side dock. Each action has its own key box: click the box and press a key combination. A currently free suggested key is shown in gray inside that box; occupied keys require confirmation before replacement. The Settings panel also has a direct Keyboard shortcuts button. Shortcuts are unbound by default. Global / all chat view can also be assigned a shortcut (suggested: CTRL-ALT-G). SmartChat checks the current binding map, shows the action already using a key, and asks before replacing it. It also re-checks after the game's binding map changes. Binding edits are disabled during combat.
  - Each tab has a speaker toggle for its sound alerts. The speaker remains visible when muted and changes color to show ON/OFF.
  - Settings subwindows open above the main Settings window and return cleanly with Back/Close.
  - Chat Text Appearance is available from the main Settings window. Choose Blizzard Default, Friz Quadrata, Arial Narrow, Morpheus or Skurri; set chat message size from 8 to 48; and optionally apply the same font to the typing box. A live sample preview and Reset to Blizzard Default are included. This affects the main chat message frame across SmartChat tabs only; it does not alter message/channel/name colors or other game UI fonts.
  - Sound & Notifications is available from the main Settings window. It has a master sound-notifications toggle, Live Preview (OFF by default), per-tab volume sliders, sound selection and Test buttons. Built-in and custom tabs can each have their own notification volume.
  - Per-play notification volume uses Forever's C_Sound.PlaySound volumeOverride; it does not change the game's global audio CVars. Name alerts use the volume of the chat tab that received the triggering message.
  - Per-tab alert sounds, unread counters, name alerts and custom alert words.
  - Settings, shortcut and copy windows are fully opaque by default; lower the SmartChat windows opacity slider to make their backgrounds transparent.
  - Optional timestamps, friend/guild/group badges and relationship-based name colors. Guild names inherit the current Guild tab color; group names inherit Party or Raid tab color, and combined relationships are calculated live from current source colors. Friend and Battle.net friend colors remain independent.
  - Optional local chat history, with retention and replay settings in /sc. This is separate from Player Journal: chat history can store message text when enabled; Player Journal stores interaction metadata only.
  - Optional word filtering and masking.
  - Per-tab display filters: Global is the aggregate view; Say, Party, Raid, Guild, Officer, Instance, Whisper and channel tabs show their own stream by default. General is limited to channel 1, and custom channel tabs match their configured channel. System, loot and NPC game notices remain visible unless you choose "This chat only"; unknown/unclassified lines are Global-only by default. Unread/sound routing follows the same separation.
  - A copy window that lets you select recent chat text and press Ctrl+C.

COMMANDS
  /sc          Open or close settings.
  /sc check    Show the client API checks available in this build.
  /sc binds    Check suggested key combinations and list possible shortcut conflicts.
  /sc route    Show selected tab, current chat type and sticky chat type for routing diagnostics.
  /sc dock     Show or hide the side icon toolbar.
  /sc copy     Open the recent-chat copy window.
  /sc newtab   Create a custom chat tab.
  /sc pin TEXT Pin a line above the tab bar.
  /sc unpin    Remove the pinned line.
  /sc pos X Y  Move the tab bar.

FOREVER NOTES
  - Uses the modern Camelot/Mainline chat edit-box API (ChatFrameUtil.OpenChat and
    EditBox:SetChatType / SetTellTarget / SetChannelTarget).
  - Optional event registrations are guarded because the Forever client may reject
    event names that are not present in its build.
  - Forever has modern in-combat secret-value restrictions. SmartChat skips operations
    on message text that the client marks secret; some text-based features can therefore
    be unavailable in restricted combat contexts.
  - Chat history is OFF by default for a fresh installation. When enabled, it stores
    message text (including whispers) in the addon's local SavedVariables file on this
    computer. You can enable or disable it in /sc and clear stored history there.
  - For security and compatibility, SmartChat never calls SendChatMessage to send a
    player's typed message. It configures the game's own chat edit box instead.

PROJECT PLAN
  - PROJECT_ROADMAP.txt is the chronological master request register. New requests are appended at the bottom and implemented oldest-first.

PLAYER JOURNAL PRIVACY AND PERFORMANCE
  - Journal data is stored locally in SmartChatDB (SavedVariables). No external server,
    web request, or background network connection is used.
  - SavedVariables are loaded with the AddOn at login, as required by WoW. The timeline
    is not built or rendered until you open a player's Journal or the Activity category.
  - Tracking is event-driven. SmartChat does not poll player lists or scan the world.
  - Whisper message content is not copied into Player Journal. Whisper chat text remains
    subject only to the separate Optional Chat History setting.
  - Default limits are 90 days, 500 events and 500 contact notes. The event limit can
    be changed in Settings > Social & Journal. Oldest automatic events are pruned first.
  - The first Friend and Guild snapshots establish a baseline and are not recorded as
    mass additions. Tracking starts from the moment you enable it.

TEST STATUS
  The Lua files have been syntax-checked and Forever-specific API calls have been
  statically reviewed. This package has not been launched inside the live WoW Forever
  client in this environment. Test social actions, Friend/Guild snapshots, group session
  tracking, Quest events and Journal persistence in-game before treating them as fully
  verified.


RIGHT-CLICK SOUND CONTROLS (0.7.12)
  Each tab's right-click menu contains a Tab Volume slider. It edits the same
  SavedVariable as the Sound & Notifications page; the two controls stay in sync.
  The menu also shows Master Volume and the effective final level. Effective level
  is Master Volume multiplied by the tab's individual volume. Master Mute suppresses
  all SmartChat audio without changing per-tab sound toggles or saved volume levels.
  The right-click Test button respects Master Mute and the effective volume, but can
  audition a selected sound even when that tab's incoming-notification toggle is off.
  Live Preview, when enabled, also applies to the right-click volume slider.

SOUND PACK (0.7.11)
  SmartChat includes ten original short notification sounds in the Sounds folder.
  Each sound has ten pre-rendered OGG variants at 10%, 20%, ... 100% gain. This lets
  the per-tab slider and Master Volume work for custom sound files without changing
  WoW's global audio settings.

  Master Volume scales every tab's individual volume. For example, Master 50% and
  Guild 80% plays Guild at an effective 40%. Mute All stops SmartChat notifications,
  Test playback and Live Preview without changing saved volume values.

  The sound selector offers a categorized picker for available built-in SoundKit sounds
  and all ten bundled Sound Pack sounds. Custom tabs can also select their own sound. Live Preview
  is OFF by default; the Test button always plays the selected sound at its effective
  volume. Sound Pack files are part of this ZIP and should stay in the Sounds folder.

  The Sound Pack sounds were synthesized specifically for SmartChat and do not use
  extracted World of Warcraft audio assets.

SOCIAL DATA BACKUP / RESTORE (0.7.25)
  - Open Settings > Social & Journal > Backup / Restore.
  - Local Save: ordinary in-game Social Hub and Player Journal data is stored in SmartChat SavedVariables and written by WoW on logout/reload. No manual copy or paste is needed during regular play.
  - Create Restore Point stores one extra local snapshot of Social Hub and Player Journal data. A portable import automatically creates a restore point first. Restore Previous State swaps the saved snapshot with the current state so you can switch back if needed.
  - Export: choose Generate & Select. SmartChat prepares and selects the portable backup text; press Ctrl+C, paste it into Notepad or another plain-text editor, and save it as SmartChat-Backup.txt.
  - Import: open the saved text file, copy all text, return to SmartChat, choose Import Backup, click the paste box and press Ctrl+V. Select Validate Backup and review the record counts before choosing Import & Merge.
  - Import is disabled until the current text is validated. Editing the text after validation requires validating it again. Malformed records and empty backups cannot be merged.
  - Import merges data and does not replace current contacts, groups, notes or history. Existing events are deduplicated. No chat message text or Battle.net account identifiers are included.
  - WoW AddOns cannot access arbitrary files or the operating-system clipboard directly. Manual copy/paste is only for portable transfer or an external copy, not for normal in-game saving.

TROUBLESHOOTING
  1. Type /console scriptErrors 1 then /reload to enable Lua error popups.
  2. Type /sc check and keep the output.
  3. When reporting a problem, include the SmartChat version, the Forever build
     (shown by /sc check), what you clicked, and the full Lua error.

VERSION HISTORY
  0.7.34 - Completed the planned Player Journal / History pass: safer Friend and Guild snapshots, per-player group attendance, zone history, coalesced Whisper interaction records, chronological timelines, optional local retention, quick notes, shared-session comparison, Insights, and portable/local recovery. Social Hub development continues in its other categories.
  0.7.33 - Added Social Intelligence, Smart Player Discovery, evidence-based Relationship Network, per-player social insights, optional Favorite/Pin suggestions and period-filtered activity summaries. Corrected shared group partner lookup and clarified Quest roster observations.
  0.7.25 - Added per-player group-session attendance (including joins/leaves/rejoins), timeline attendance details, a Local Save page and one-click local restore points with automatic protection before portable imports.
  0.7.24 - Redesigned Social Backup / Restore with separate Export/Import pages, data summary, automatic text selection, safe validation and merge preview.
  0.7.23 - Added expanded Player Journal profiles, timeline filters, group-session metadata and local backup/restore.
  0.7.22 - Added local Social Activity presence/roster tracking and opt-in in-game notifications for Friend, Guild, Group and Battle.net events.
  0.7.21 - Added clickable web/Discord URL detection and a copy box while preserving native WoW hyperlinks.
  0.7.20 - Expanded Battle.net account visibility, Guild Rank/Level/Class sorting and Guild/Group roster details.
  0.7.19 - Added Social Hub contact tools, custom groups, quick actions and optional local Player Journal.
  0.7.18 - Added relationship badges, Class/Level and presence details to the vertical Whisper contact list.
  0.7.17 - Added the vertical contact sidebar to the single Whisper tab.
  0.7.16 - Restored the independent Social Hub dock icon and Whispers category while retaining one main Whisper tab.
  0.7.12 - Added synchronized per-tab volume controls to tab right-click menus, with Master/Effective readouts and Live Preview support.
  0.7.11 - Added 10 original bundled notification sounds with 10%-100% gain variants, per-tab selection, Master Volume, Mute All, and Live Preview integration.
  0.7.10 - Resized and repositioned the shortcut buttons in the main Settings window.
  0.7.9 - Added Sound & Notifications settings, per-tab volume, master sound toggle and optional live preview.
  0.7.8 - Fixed strict per-tab chat isolation and General/custom-channel filtering. Added a one-time migration for old generated filters while preserving user-edited filters. Unknown/unclassified lines are Global-only by default.
  0.7.7 - Relationship name colors inherit current Guild/Party/Raid tab colors. All combinations are calculated dynamically; Friend and Battle.net colors remain independent.
  0.7.5 - Added Global aggregate chat view, independent unread state, one-sound-per-message notification routing, own-message exclusion from unread/sounds, and a Global keyboard shortcut action. Global view preserves the last real chat-send destination.
  0.7.4 - Constrained tab drag-and-drop to the horizontal tab strip; vertical movement is locked and drops outside the strip cancel.
  0.7.4 - Tab dragging is constrained to the horizontal tab strip; releasing outside the strip cancels the drag.
  0.7.3 - Fixed actual drag-and-drop movement and saved tab reordering. Restored visible speaker indicators on all tabs. Replaced translucent dialog backgrounds with solid backgrounds controlled by the opacity slider.
  0.7.2 - Moved the utility dock to the LEFT of the chat panel. Selecting a tab now
          applies its chat type/sticky type to the actual send edit box (including the
          last-active/docked box in IM chat style), even while hidden. Added /sc route
          diagnostics and warnings when Party/Raid/Instance/Guild destinations are unavailable.
  0.7.1 - Added an in-AddOn shortcut editor, occupied-key confirmation, automatic
          binding-change monitoring, a keyboard dock icon and drop-position tab reordering.
  0.7.0 - Added no-focus tab selection by default, optional old behavior and the side icon dock.
  0.6.1 - Forever-specific package: interface 16001; modern chat edit-box routing;
          full-name/surname-safe player matching; guarded event and filter registration;
          updated Forever installation instructions and diagnostics.


Social Hub and Single Whisper Tab (0.7.16)
Social Hub remains an independent dock icon and opens its own compact contact window. Its Whispers category shows the same recent private-conversation contact list used by the main Whisper tab. The main chat bar contains exactly one Whisper tab. When selected, a second row of contact tabs appears above the main SmartChat tab strip, styled like the regular chat tabs. Selecting a contact filters the normal chat frame to that person's conversation and routes replies to them. The recent contact list is saved in SavedVariables (up to 20 contacts); message preview text remains session-only. No per-player main tabs or separate Whisper windows are created. This version has not been tested inside the live WoW Forever client.

Whisper Preview (0.7.13)
Social Hub retains the recent Whisper preview. Messages are session-only and are not added to SavedVariables.

Name Color Mode (0.7.13)
Settings > Chat Appearance > Name color mode switches between Relationship (default) and Class. This setting changes player names only; message text and channel colors remain unchanged. Changes apply to new chat lines.



WHISPER CONTACT SIDEBAR (0.7.17)
When the single Whisper tab is active, a compact vertical list of recent Whisper contacts appears inside the main chat window on the left. The selected player's conversation is shown in the normal chat message area on the right. Selecting another contact changes the filter for that one Whisper tab; it does not create additional main chat tabs or floating windows. Contact rows use the same visual language as SmartChat tabs. The Social Hub remains available from its own dock icon and still includes a Whispers category.


WHISPER CONTACT DETAILS (0.7.18)
The vertical contact list shows the same relationship badges used by SmartChat chat lines, plus the selected name color mode, a presence dot, and Class / Level beneath each name. Missing class or level values are shown as Unknown / Lv. ?. Friend, Guild, Group and available Battle.net presence are combined without allowing a basic online flag to overwrite an explicit AFK or DND state. Badge and name-color setting changes refresh the Whisper list and Social Hub immediately.


WEB LINK HANDLING
  - Plain HTTP/HTTPS, www, Discord invite and common bare-domain addresses in visible chat lines are converted into local clickable links.
  - Clicking a detected address opens a small SmartChat copy box with the complete address selected; press Ctrl+C, then paste it into your browser or Discord.
  - Web link handling can be disabled in Settings. The popup is suppressed during combat.
  - SmartChat does not make network requests for URL detection and does not automatically launch an external browser. The game's external-link APIs are restricted; the copy box is the safe fallback.
  - Native WoW item, spell, quest, achievement and player hyperlinks are left unchanged.
  - Link detection runs only on chat text that the client exposes to the addon; it does not bypass Blizzard's chat security restrictions.

OTHER LINK-RELATED FEATURES
  - The Copy dock button opens a window for selecting and copying recent chat text.
  - Ctrl+click on a player name in chat can prepare a quoted reply in the same channel (where supported and enabled).


0.7.21 - Web Link Handler
- Plain HTTP/HTTPS, www, Discord invite and common bare-domain addresses in chat can be turned into local clickable links.
- Clicking a web link opens a small SmartChat copy box with the full address selected; use Ctrl+C to copy.
- SmartChat never launches an external browser and makes no network requests for link handling.
- Web link handling can be disabled in Settings. Link clicks are suppressed during combat.
- Existing World of Warcraft hyperlinks (items, spells, quests, players, achievements) retain their normal handling.


0.7.21 - Web Link Handler
- Added optional clickable web and Discord addresses in chat.
- Clicking a detected web address opens a small copy box with the URL selected for Ctrl+C.
- No external browser launch or network requests; link clicks are suppressed during combat.
- Existing native WoW hyperlinks retain their normal behavior.
- Not yet tested inside the live WoW: Forever client.


PLAYER PROFILE SECTIONS (0.7.26)
The Social Hub profile area now has four views: Overview, History, Notes and Relationship. Overview summarizes recorded interactions, group attendance, the most frequent shared group partners and recent Whisper interaction dates. History retains the existing event-type and time-range filters. Notes shows saved quick tags, optional personal text and its last-updated time. Relationship shows current Friend/Battle.net/Guild/Group signals, Favorites, Pins, private contact groups and recorded relationship events.

Shared group partners are calculated only from stored group-session events in which the selected player and the other player both have recorded attendance. The value means both players appeared during the same recorded group session; it does not prove they were present at the exact same moments, that a dungeon was completed together, or indicate a player's quality. Old sessions without individual attendance remain estimated. The profile summary is calculated when the relevant Social Hub view is refreshed; no periodic polling or network activity is added.


0.7.27 NOTES AND LOCAL DATA MANAGEMENT
- Social Hub has a dedicated Notes category listing contacts with saved quick tags or private notes.
- Select a contact in Notes to review or edit their note. Delete Note requires confirmation and leaves event history untouched.
- Right-click a contact and choose Clear Local Journal Data to remove that player's local event references and private note. Shared group and quest records remain for other participants.
- Clearing all completed Journal events now requires confirmation and creates a local recovery point first.
- In-game Friends, Guild and Ignore lists are never changed by SmartChat's local Journal cleanup.


0.7.28 SOCIAL DASHBOARD AND GROUP MANAGEMENT
The Social Hub Overview includes five clickable summary cards: Friends, Guild, Whispers, Favorites and My Groups. Click a card to open the corresponding category. Values are read from current game data and local SmartChat data when the Hub refreshes; no polling or network activity is used.

In the Groups category, left-click the group selector to cycle through All and your custom groups. Right-click a selected custom group to open Rename Group or Delete Group. Renaming preserves the members and group order. Deleting a group asks for confirmation and creates a local restore point first. You can continue to add or remove a contact from several personal groups using the contact right-click menu.


Version 0.7.29 additions
- Player Profiles include a Shared section for comparing recorded group sessions with another known player.
- In the Shared section, left-click Compare to cycle forward through recorded group partners; right-click to cycle backwards.
- Each shared session reports per-player recorded attendance and may label older records as estimated. Shared membership does not prove exact simultaneous overlap or dungeon completion.


0.7.29 SHARED GROUP HISTORY COMPARISON
  - Player Profiles include a Shared section for comparing recorded group sessions between the selected player and another known group partner.
  - In the Shared section, left-click Compare to cycle forward through recorded group partners; right-click to cycle backward.
  - Shared-session rows show session date, title, group kind, group size, difficulty and known locations, plus each player's recorded attendance time and visit count.
  - The comparison uses only local group events where both players are recorded participants. Older records without individual attendance are marked estimated.
  - Shared group membership does not prove exact simultaneous overlap, dungeon completion or quest completion.
  - The existing timeline time-range filter also applies to shared-session comparisons.


Version 0.7.31 additions
- Added a Quick Contact Filter control to Social Hub. Left-click cycles All, Available, Online, Offline, AFK, DND, Unknown, Favorites, Pinned, Unread and Has Notes; right-click resets to All.
- Search now also matches status, level, role, Guild name, Favorite/Pin state and unread state, in addition to names, class, zone, rank, BattleTag, private groups and personal notes/tags.
- Added Unread to contact sorting so conversations with the most unread messages can be brought to the top (after pinned and favorite contacts).
- Existing Online only preferences migrate to the Available filter without changing their previous behavior.
- Search, filters and sorting remain local and are calculated only when the Social Hub list refreshes. No network activity, polling loop or persistent background timer is used.

Version 0.7.30 additions
- Open Customize from the Social Hub header.
- Show or hide Social Hub categories and change their order with the up/down controls. Overview remains available.
- Show or hide Player Profile sections and change their order. Overview remains available.
- Choose Compact or Comfortable contact rows and independently show or hide status dots, relationship badges, Class/Level, personal group labels and Favorite/Pin markers.
- Control the social notification master switch and individual event notifications from the same panel. These settings remain synchronized with Settings > Social & Journal.
- Reset Layout Defaults restores only display preferences; it does not erase social data or notification choices.
- All choices are saved locally in SmartChatDB. The customization panel performs no background polling or network requests.


Version 0.7.32 - Battle.net Account / Game Account Context
- Linked each Battle.net friend account to the game-account records currently exposed by the client API.
- The BNet category keeps account-only contacts visible and shows account context for WoW character rows, including BattleTag/display name, reported game-account count, realm and known game presence.
- Selecting a WoW character now shows other currently reported game accounts and WoW character records associated with the same Battle.net friend account. Non-WoW game presence is shown when the API exposes a client/game label or rich-presence string.
- The default BNet list sort groups character rows by Battle.net account display identity; search also matches linked characters, realms, game labels and rich-presence text.
- Deduplicated the account-level gameAccountInfo and indexed GetFriendGameAccountInfo records so one game account is not listed twice when both APIs describe it. Account-level Online status is aggregated from reported game accounts without overwriting per-character presence.
- Battle.net account and game-account identifiers remain in-memory session data only. They are not written to SavedVariables or portable backups. The UI explicitly states that this is the currently reported game-account data, not a complete character roster.
- Kept non-WoW and offline Battle.net contacts visible without exposing invalid Whisper/Party actions.
- Syntax-checked all Lua files and tested account/game-account grouping, duplicate removal, multi-account status aggregation and offline/non-WoW account visibility with mocked API data. Not tested inside the live WoW: Forever client.
  - History safety: a temporary Friend API read failure is ignored instead of being recorded as an empty roster; changing or leaving your own Guild is recorded as one character-level Guild context event and is not misreported as every former Guild member leaving. Turning Player Journal or Group tracking off first closes and saves an active group session. Whisper interaction entries are coalesced per contact in a 15-minute window and sorted by their latest interaction; no Whisper content is stored. History only begins when tracking is enabled and is never backfilled from events that happened before installation or activation.
