# Changelog

All notable changes to EasyFind Chat will be documented in this file.

---

## [1.3.0] - 2026-11-23

### Added
- **Find a chat by name**: typing a friend's name in EasyFind's search finds your chat with them, with no @chat or chat word first
- **Search switches on the settings page**: Conversations and Messages, what EasyFind's search finds of your chats, are on the chat's settings page as well as in the filter menu

### Changed
- Marked up to date for WoW 12.1.7, so the game no longer lists it as out of date there

---

## [1.2.1] - 2026-11-22

### Fixed
- **Whisper chats stay one chat**: a whisper with someone on your realm keeps to the same chat in a session where the game gives no realm name. It could open as a second, empty one (with EasyFind 5.6.0)

---

## [1.2.0] - 2026-11-22

### Added
- **One ignore list for all your characters**: Ignore on the right-click menu of a message or a whisper chat hides that player's messages on every character. Each character adds the names to its own in-game ignore list when it logs in, and names already on a character's in-game list join the shared one. Unignore, or removing the name in the game's own list, takes it off everywhere. The Ignore List button in the chat's settings shows everyone on it
- **Report Player**: on the right-click menu of another player's message, it opens the game's report window on that message. The row is grayed on a message the game no longer holds

### Fixed
- **The open chat is remembered**: after a reload or a login the window opens on the chat you had open on that character, instead of the top one in the list

---

## [1.1.0] - 2026-11-13

### Changed
- **Notifications are for private messages by default**: only whispers and Battle.net whispers count on the chat button and play the message sound. Party, raid, instance, guild and officer chat start muted, as Say, Yell and the channels already did; a message that names you still counts. The new switch Mute group and guild chat turns this off, and a chat's own Mute or Unmute still wins

### Fixed
- **Battle.net chats**: each chat stays with its friend after a logout. Before, a chat could show another friend's name or none, a new whisper could land in another friend's chat, and a reply could reach a different friend. Chats saved earlier are sorted by friend on the first login; lines already filed under the wrong friend stay where they are

---

## [1.0.2] - 2026-11-09

### Fixed
- **The chat button's count**: counts the conversations the list shows, this character's, not every character's
- **WoW Forever**: a chat line the client withholds (a level-up's "You have learned a new spell") no longer raises an error
- **A client dialog's text box** with the keyboard focus no longer raises an error when the messenger looks at the focus
- **An EasyFind older than 4.0.0** gets one chat line asking for the update instead of errors

---

## [1.0.1] - 2026-11-03

### Fixed
- **Sidebar**: the conversation list runs down to the line under it, its last row cut there, instead of stopping short with a gap

---

## [1.0.0] - 2026-10-21

### Added
- **The messenger**: whispers and channels as conversations with threads and history, a composer with recipients and channel suggestions, emotes, and a window that folds its header or title away
- **In EasyFind**: a Chat tile in the extensions menu, a launcher row for the typed name, and the search bar finds conversations and messages and sends results and notes to a conversation
- **Notes**: Ctrl+Right-click on a link in the messenger opens its note
- **Clients**: retail, WoW Forever, Classic Era and TBC Anniversary
