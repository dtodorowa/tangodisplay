# TangoDisplay

A native macOS menu-bar app that shows a clean, fullscreen dancer display on an external monitor at milongas. It monitors Music.app in real time via system notifications, with AppleScript polling as a fallback, automatically detects cortinas, and shows track info — artist, title, genre, year, and tanda position.

![TangoDisplay in action](docs/screenshots/DisplayCoverImage.png)

---

## Features

- **Built-In Player** — native audio player: build a setlist by dragging tracks from Finder, Music.app, or Swinsian; full playback controls with accidental-stop protection; Fade & Stop / Fade & Continue cortina transitions; real-time dual-channel level meter with peak hold and clip detection; stereo balance control; 5-band EQ (±12 dB); audio output routing to any macOS device; optional duplicate track protection; auto-gap silence detection pads the gap between tracks to a configurable minimum; export setlist to M3U8 or Apple Music playlist; setlist persists across restarts. No Music.app required.
- **Track Info Transformations** — optional regex-based rules let you reformat how Artist, Title, Year, Album Artist, and Comments appear on the display screen without touching the original music tags. Transformations are configured per-field in **Settings › Advanced** with a live preview before saving.
- **Live track display** — artist, title, genre/label, year, and track counter (e.g. Track 2 of 4) on the dancer screen
- **Cortina detection** — configurable allowlist (cortina genres) and denylist (dance genres) with partial matching; shows a "CORTINA" overlay automatically. Optional per-entry **display label** lets you show a clean label (e.g. `Vals`) instead of the raw genre tag (e.g. `Tango: Vals`)
- **Coming-up preview** — displays the next tanda's genre and artist before it starts
- **Multi-monitor support** — sends the presentation window to any connected display; move and toggle fullscreen from the control window
- **Appearance profiles** — built-in (Classic, Modern, High Contrast) and unlimited custom profiles with per-field colors, fonts, and background image
- **Background image** — any image with opacity, scale, and pan controls
- **Artist Backgrounds** — per-profile list of artist name → background image mappings; when the playing track's artist contains a configured name (partial, case-insensitive, Unicode-safe match), that image replaces the profile background. Falls back to profile background image then background colour. Configurable opacity, scale, and position. Active only during dance tracks — clears automatically on pause or stop.
- **Transitions** — configurable fade style and duration between tracks
- **Global hotkeys** — `⌘⇧O` override, `⌘⇧P` pause display, `⌘⇧R` force-refresh, without switching windows
- **Mirror mode** — live preview of the presentation window in the control window
- **Display labels** — customisable "CORTINA", "COMING UP", and idle message text
- **Idle message** — optional text shown when nothing is playing
- **Field visibility** — independent show/hide toggles for every display field (Genre, Artist, Year, Title, Singer, Artwork) with separate **Dance** and **Cortina** columns. Hides the entire "Coming Up" next-track preview during cortinas with a single toggle. A second **Show cortina track during cortina** section lets you optionally display the playing cortina's own artist and/or title.
- **Album Artwork** — display the current track's artwork on the dancer screen; enable per context (dance tracks, cortinas, or both) with configurable opacity, scale, and position. Supported for Music.app, Swinsian, and Embrace.
- **Singer line** — display the vocalist name; choose the source — **Comments** or **Album Artist** — via the Singer Source picker in Appearance. Configurable font and color. Enable per context (dance tracks, cortinas, or both). Supported for Music.app, Swinsian, and Embrace.
- **Text order** — drag items into any order you like for three independent sections — dance-track display, cortina track display, and the cortina "Coming Up" preview — per appearance profile
- **Player Source** — choose Music.app (default), Swinsian (real-time notifications; queue-based look-ahead), Embrace (full playlist lookahead and tanda counting via AppleScript), JRiver Media Center (MCWS HTTP API; full playlist lookahead and tanda counting; zone selection lets you pin TangoDisplay to a specific zone so a pre-listening zone never affects the display), MegaSeg Pro (Beta; reads program-deck output via NowPlaying logs; genre from MegaSeg's library database), or the Built-in Player. See [Supported Players](https://github.com/richardsladetdj-creator/TangoDisplay/wiki/Supported-Players) for a full feature matrix.
- **Update indicator** — a small dot in the sidebar shows when a newer release is available; click to open the releases page

---

## Requirements

| Requirement | Detail |
|---|---|
| macOS | 13 Ventura or later (Intel and Apple Silicon) |
| Music.app | Required only when using Music.app as the player source. Not needed with the built-in player. Must be running and playing from a playlist. |
| Swinsian | Required only if selecting Swinsian as the player source in Settings › Player. |
| Embrace | Required only if selecting Embrace as the player source in Settings › Player. |
| JRiver Media Center | Required only if selecting JRiver as the player source. Must be running with Media Network enabled (Tools → Options → Media Network). Connects to 127.0.0.1 on the default MCWS port (52199). If using multiple zones, select the output zone in Settings › Player › Zone. |
| Xcode Command Line Tools | `xcode-select --install` — no full Xcode needed |

---

## Installation

### Option A — Download pre-built app (easiest)

1. Go to the [Releases](https://github.com/richardsladetdj-creator/TangoDisplay/releases) page
2. Download `TangoDisplay-v3.31.0-universal.zip` (works on both Apple Silicon and Intel Macs)
3. Unzip and drag `TangoDisplay.app` to your `/Applications` folder
4. **Right-click › Open** on first launch (required because the app is ad-hoc signed, not notarised)
5. Grant the permissions macOS requests (see [Permissions](#permissions) below)

### Option B — Build from source

```bash
# Clone the repo
git clone https://github.com/richardsladetdj-creator/TangoDisplay.git
cd TangoDisplay

# Build, bundle, sign, and install to /Applications in one step
./Install.sh
```

`Install.sh` requires Xcode Command Line Tools (`xcode-select --install`). It will:
- Regenerate the app icon
- Build a universal binary (arm64 + x86_64) using `swift build` and `lipo`
- Assemble `TangoDisplay.app` with a correct `Info.plist`
- Ad-hoc code-sign the bundle
- Install to `/Applications` and launch the app

---

## Permissions

On first launch macOS will prompt for two permissions:

| Permission | Why it's needed |
|---|---|
| **Automation › Music** | TangoDisplay reads the currently playing track, artist, genre, playlist position, and upcoming tracks via AppleScript |
| **Input Monitoring** | Required for the global hotkeys (`⌘⇧O`, `⌘⇧P`, `⌘⇧R`) to work while other apps are in focus. Grant in **System Settings › Privacy & Security › Input Monitoring** |

> Global hotkeys silently do nothing if Input Monitoring is denied — everything else works fine without it.

---

## Quick Start

1. Start Music.app and play a playlist
2. Launch TangoDisplay — a small display icon appears in the menu bar
3. Click the menu bar icon › **Show Settings Window**
4. Go to **Display** and select your external monitor as the target display
5. Click **Move Presentation Window** then **Toggle Fullscreen**
6. The dancer display is live — go to **Appearance** to customise colors, fonts, and background

See the **[Wiki](https://github.com/richardsladetdj-creator/TangoDisplay/wiki)** for a full user guide with screenshots.

---

## Building and Testing

```bash
# Debug build
swift build

# Run all tests (39 tests, custom runner — no Xcode needed)
swift run TangoDisplayTests

# Full release build → /Applications (same as install)
./Install.sh
```

---

## Architecture

The project has three SPM targets with no external dependencies:

| Target | Type | Purpose |
|---|---|---|
| `TangoDisplayCore` | Library | Pure logic — cortina detection, tanda tracking, models. No AppKit/SwiftUI. |
| `TangoDisplay` | Executable | SwiftUI app — UI, AppleScript bridge, polling, settings, window management |
| `TangoDisplayTests` | Executable | Lightweight custom test runner (`swift run TangoDisplayTests`) |

Key design decisions:
- `NSAppleScript` runs on a dedicated background serial queue (avoids blocking the main thread)
- Playlist lookahead is fetched on every cortina transition (for accurate "Coming Up" info) and also refreshed every 20 seconds via the periodic fallback poll
- Profiles are stored as JSON in `~/Library/Application Support/TangoDisplay/profiles/`
- Colors are stored as hex strings in `AppearanceProfile` (Codable)
- `ObservableObject` + `@Published` throughout (macOS 13 target predates `@Observable`)

---

## Changelog

### v3.31.0
- **Shellac Restoration:** new Restoration button in the Setlist toolbar, with Declick and Dehum filters for 78 rpm transfers, running ahead of the equaliser. Off by default. Per-track overrides (right-click a row) outrank both the master switch and the cortina skip, so a single shellac transfer can be repaired in an otherwise unrestored set. The filters are the DSP cores from [ShellacFilters](https://github.com/shaforostoff/shellacfilters) by Nick Shaforostov (MIT), built on the [Airwindows](https://www.airwindows.com) framework by Chris Johnson; the Audio Unit wrapper is adapted from [EmbraceNG](https://github.com/shaforostoff/EmbraceNG) (© 2024 Ricci Adams). See [Credits](#credits).
- **Music start/stop times re-read on every drop:** trim markers imported from Music (Song Info → Options) now reflect edits made after TangoDisplay launched, and are imported correctly for iTunes-purchased tracks that arrive as file promises. Previously the times were read once per session and matched by file path.
- **Slider knobs on macOS 26:** sliders in the EQ, Balance, ReplayGain and Auto-gap popovers no longer draw a track with no knob until first clicked.

### v3.30.0
- **Skip gap after manual stop:** new option in Settings › Player › Auto-gap. When a track is stopped before it ends, the next track you start plays immediately with no silence preroll. Covers the transport stop button and Fade & Stop. Off by default, so existing behaviour is unchanged.

### v3.29.1
- **Sub-second trim precision:** the Track Start & End editor now accepts tenth-of-a-second times (`m:ss.d`) and allows windows as short as 0.1s.
- **Auto-gap respects trims:** silence past a trimmed end or before a trimmed start is no longer counted toward the auto-gap target, so trimming a track no longer collapses the gap before the next one.
- **Missing-file drop alert:** dropping tracks whose files can't be found now shows an alert dialog instead of a brief inline note.

### v3.29.0
- **Import Music start/stop times as trim markers:** when the built-in player is active, dropping tracks from Music now reads each track's start/stop times (Song Info → Options) and applies them as playback trim markers automatically.
- **Skip missing files on drop:** tracks whose underlying file no longer exists (shown with a warning triangle in Music) are now rejected on drop with a "not found" note, instead of silently being skipped at playback.
- **Genre lists now stored as JSON:** allow/deny genre lists are saved as JSON rather than comma-joined text, so genres containing a comma work correctly. Existing settings migrate automatically.

### v3.28.1
- **Fixed a crash (JRiver):** rapidly rebuilding or re-picking the Playing Now list could momentarily leave JRiver without a valid playing position, which crashed TangoDisplay while showing the next track during a cortina. The playlist position is now clamped safely.

### v3.28.0
- **Track Start & End Time (Built-in Player):** new context-menu action to trim any track's playback to a sub-range — replay a track from a mid-point (e.g. during applause after a performance). Editor window with draggable start/end handles over the waveform (dulled outside the selection) plus manual m:ss entry. Trimmed tracks show a start–end badge; **Clear Start & End Time** removes it. Works with Repeat Track (loops the trimmed range).

### v3.27.0
- **Repeat Track (Built-in Player):** mark a non-dance track to repeat until 'stop-after' or un-marked. Blue repeat icon, context-menu toggle, mutually exclusive with stop-after (confirm alert), cleared by fade actions.
- **Fixed (Built-in Player):** context menu now correctly resumes auto-gap on the first track when auto-gap is auto-applied by the global setting.

### v3.26.6
- **Fixed (Built-in Player):** auto-gap silence could be applied to the wrong track after reordering, skipping, or marking tracks played; silence analysis is now bound to the exact track transition

### v3.26.5
- **Improved (Setlist):** when *Hide Played* is on, a banner now shows how many played tracks are hidden

### v3.26.4
- **Improved (Built-in Player):** setlist playback now continues uninterrupted even when the Mac would otherwise idle-sleep (notably on battery)
- **Improved (Built-in Player):** dragged-in tracks now appear instantly and fill in their details a moment later, instead of seeming to fail
- **Improved (Built-in Player):** cloud-only Music.app tracks in a mixed selection are now downloaded and added in full rather than being silently skipped
- **Improved (Setlist):** the duplicate-track prompt now reports how many tracks are affected and whether they were already played, with a brief on-screen note when duplicates are skipped

### v3.26.3
- Revert "Mark as Played / Not Played" no longer leaves a played track stranded below a queued one. Fixes mark as played selection not working on single tracks.

### v3.26.2
- **Fixed (Built-in Player):** after pausing a track and dragging another queued track above it, pressing play now starts the new top track instead of resuming the paused one
- **Fixed (Setlist):** "Mark as Played / Not Played" no longer leaves a played track stranded below a queued one — the played block stays a contiguous group at the top

### v3.26.1
- **Fixed (Custom Text Lines):** deleting a custom line — especially immediately after adding it — could crash the app. The visibility and editor lists now use stable id-keyed bindings instead of array-index bindings, so deletes are safe regardless of timing

### v3.26.0
- **New (Custom Text Lines):** add unlimited free-text lines to the display for dance tracks and the cortina "coming up" preview. Each line supports metadata placeholders (`{Artist} {Title} {Genre} {Year} {Singer} {AlbumArtist} {Comment} {Grouping}`, case-insensitive), its own font, size, bold/italic and colour, independent Dance / Next Up visibility, and can be reordered among the built-in fields. Managed in Appearance › Visibility › Custom Lines

### v3.25.5
- **Fixed (Setlist paste):** pasting tracks copied from foobar2000 now works — foobar2000 writes file paths as bare POSIX strings rather than `file://` URLs, which the previous clipboard reader missed
- **Fixed (build):** resolved a Swift type-checker timeout that broke the build on older Intel Macs

### v3.25.4
- **Fixed (Setlist + JRiver):** when dragging a mixed batch of tracks with Duplicate Protection enabled and "Add" chosen for all duplicates, duplicate tracks could appear before fresh tracks at the drop position — now all tracks insert in original drag order at the correct position

### v3.25.3
- **Fixed**: drag insert position now always respected when Duplicate Track Protection is enabled — previously, accepted duplicate tracks were appended to the end of the setlist instead of the drop position

### v3.25.2
- **DJ Name**: show your name on the dancer display — configurable corner or centred position, with a "Show when" control (any track playing / idle & paused / always)
- **Fixed**: when dragging a mixed batch with Duplicate Protection on, duplicates could be inserted at the drop position instead of the end of the setlist

### v3.25.1
- **Waveform window reliability**: fixed intermittent "No track playing" flashes during track-to-track transitions and when pausing an early-marked track; the waveform now stays connected throughout
- **Waveform toolbar button**: the button is now enabled whenever tracks are loaded in the setlist, not only when a track is actively playing

### v3.25.0
- **Performance Mode**: mark any setlist track as a performance track (right-click › Mark as Performance). When it plays, the dancer display switches to a custom performance view with a dedicated background image and fully configurable text lines — font, size, colour, and `{title}` / `{artist}` / `{genre}` / `{year}` placeholders. A "Show during cortina" option pre-announces the performance on the cortina screen. Playback stops automatically after each performance track by default (toggle in Player Settings).
- **Waveform Window**: a compact floating window showing the audio waveform of the current track with a live playhead, elapsed time, and total duration. Open it via the Waveform button in the Setlist toolbar.
- **Track Tagging**: colour-code any setlist track for visual organisation. Right-click › Tag Colour to assign red, orange, yellow, green, blue, or purple. A coloured dot appears on the row and tags persist in the saved setlist.

### v3.24.4
- New Set Timings window: click the status bar timing info to open a floating dashboard showing total set time, remaining tracks, next cortina countdown, and estimated end time in large-format display
- Fix: Dragging in tracks once all played and 'Hide Played' is ON, now performs correctly

### v3.24.3
- **Fixed crash when playing a mono audio file with an AU plugin active** — mono audio is now automatically upmixed to stereo before reaching the plugin chain (via `AVAudioMixerNode`), so the plugin stays active and processes the track correctly. Previously the incompatible plugin was disabled as a workaround; it now works as expected.

### v3.24.2
- **Plugin Configurations**: save and recall named AU plugin chain settings; assign a configuration to individual setlist tracks; tracks with an assigned configuration display a badge in the setlist
- **Fixed crash when playing a mono (or otherwise format-incompatible) audio file** while a stereo-only AU plugin (e.g. FabFilter Transient Gizmo) is active; the incompatible plugin is now gracefully disabled instead

### v3.24.1
- **More third-party plugins now appear**: the plugin browser also lists **Music Effect** Audio Units (`kAudioUnitType_MusicEffect`), not just plain effects — so plugins such as **FabFilter Pro-Q 4** that register as music effects now show up and can be added to the chain.
- **Fixed a crash when opening some third-party plugin editors** (e.g. FabFilter Pro-Q 4). Plugins now load **out-of-process by default** so a plugin's editor or processing crash is isolated from TangoDisplay. A small in-process allowlist (currently Klanghelm MJUC) keeps plugin-driven window auto-resize working where it's needed.

### v3.24.0
- **Audio Unit Plugin Chain** (new): the Setlist player can now host **up to 4 Audio Units in series** instead of a single Apple-bundled plugin. Configure the chain in **Player Settings › Audio Unit Plugins**: add plugins, reorder with the up/down arrows, replace or remove individual slots, open each plugin's editor window, and save/recall presets per slot. A toolbar popover in the Setlist view gives quick chain access for live use — bypass the whole chain, toggle individual slots on or off, and open editor windows.
- **Third-party plugins supported**: the browser now lists every `kAudioUnitType_Effect` Audio Unit installed on the system (e.g. FabFilter Pro-Q4, Klanghelm MJUC), not just the curated Apple effects. AUv3 plugins load out-of-process via XPC so a plugin crash is isolated from TangoDisplay; AUv2 plugins load in-process. **Third-party Audio Units run at your own risk** — an unstable plugin may still interrupt playback.
- The legacy single-plugin setting from previous versions is migrated automatically into slot 1 of the new chain on first launch.

### v3.23.0
- **Setlist Remote** (new): toggle on in **Settings › Player › Setlist Remote** to control volume, cortina volume, and replay gain from your phone over Wi-Fi. A built-in web page shows the URL and a QR code; a 4-digit PIN regenerates each time the app launches.
- **Genre Backgrounds** (new): enable in **Appearance › Artwork & Motion** to assign a background image per genre (and one for cortinas), driven by your Cortina Rules entries. Priority: artist → genre → profile background → background colour.
- **Multi-line Advanced Transformations**: use `\n` in a transformation's *Replace with* field to split the displayed value across lines (also `\r`, `\t`, `\\`). The live preview renders the wrapped result.
- **Album Artwork Edge Fade** (new): new slider in **Appearance › Artwork & Motion › Album Artwork** that softly fades the edges of album art into the background.

### v3.22.1
- **Fix**: dragging a large multi-track selection from Music.app into the Setlist no longer truncates to a handful of tracks. The drop handler was reading the Music-specific promise pasteboard flavor (present on only a subset of items) instead of `public.file-url` (present on nearly every item), causing the rest of the selection to be silently dropped.

### v3.22.0
- **Startup Mode** (new): choose how TangoDisplay launches in **Settings › Startup**. *Full Experience* opens both the Live Display and Settings window with Settings brought forward. *Player Focused* starts the Live Display minimised to the Dock with Settings focused — restore it any time from the menu bar icon or Dock.
- **Hide Left Menu Bar on Startup** (new): collapse the Settings sidebar at launch. Expand it again at any time.
- **Cortina volume**: new slider in **Settings › Player › Cortinas** (-10…0 dB) that attenuates the playback level of tracks identified as cortinas on top of ReplayGain. Default 0 dB (off).

### v3.21.10
- Fixed: with **Hide Played** on, returning to the Setlist tab after switching to another tab no longer briefly hides (or de-emphasises) the currently playing track when it is past its mark-as-played threshold.

### v3.21.9
- Fixed: with **Hide Played** on, dragging in new tracks now lands in the correct slot. Reordering and deleting rows in the filtered list also now affect the row you actually clicked. (Previously, hidden played tracks caused offsets to be resolved against the unfiltered list, so the wrong row was targeted.)

### v3.21.8
- Hide Played: new toolbar toggle (filter icon) that hides fully-played tracks so the current track stays at the top of the visible list. The active track is always shown even when early-marked as played. Preference is persisted across sessions.
- Fixed: unplugging headphones (or any audio device change) on the System Default output no longer causes the current track to skip unexpectedly.
- Fixed album artwork overflowing its panel — artwork is now constrained to the same size as the setlist logo placeholder.

### v3.21.7
- Decibel Meter: real-time room noise monitor in the Setlist toolbar. Enable in **Settings › Player › Decibel Meter** and set your acceptable noise range with the interactive colour-coded slider (blue = too quiet, green = acceptable, red = too loud)
- Practical Use Case: As the noise level can often vary between the DJ booth and the floor, set the noise level with a professional noise meter at floor level. Measure at the desk and set the acceptable range in Setlist.
- Built-in Player settings reorganised into logical groups (Playback, Cortinas, Safety, Appearance) for clarity
- Updated app icon

### v3.21.6
- Track counter position is now configurable: top-left, top-right, bottom-left, bottom-right, or centred inline with track text
- When set to "Centred (in text order)", the counter appears as part of the text stack and can be reordered via Appearance > Visibility > Text Order for Dance Tracks
- Position setting is in Display > Control Window, below the Show Track Counter toggle

### v3.21.5
- Setlist: status bar now shows total duration when two or more tracks are selected
- JRiver Media Centre: fixed an issue where the next-track display could briefly show a stale cortina after a playback position update

### v3.21.4
- Fix: iTunes-purchased AAC tracks downloaded on macOS Sequoia can now be dragged from Music.app into the Setlist — Music.app on Sequoia delivers these via a different pasteboard mechanism that earlier versions did not handle
- On first launch macOS now prompts to allow access to your Apple Music library, which is required for these drags to be routed by the system

### v3.21.3
- Fix: Music.app drag-and-drop now uses an AppKit drop handler with direct NSPasteboard access, so the drop zone correctly highlights and accepts tracks that Music.app no longer provides as file URLs (post-~July 2022 purchases)

### v3.21.2
- Fix: tracks dragged from Music.app (post-~July 2022 purchases) now land in the Setlist correctly — Music.app no longer includes a file URL in the drag pasteboard for these tracks, so TangoDisplay now resolves them via AppleScript instead

### v3.21.1
- Fix: tracks purchased from Apple Music after July 2022 can now be dragged directly from the Music library into the Setlist on macOS Sequoia (previously the drop zone did not highlight and the file was silently ignored)

### v3.21.0
- Audio Unit plugin presets: save named presets, apply factory presets, and auto-restore the last-used preset when the plugin loads
- Preset bar added to the plugin floating window — "Preset:" picker and "Save as Preset…" button accessible without opening Settings
- Preset label resets to None when you edit any parameter directly in the plugin window

### v3.20.1
- Fix: Changing the audio output device while a setlist track was paused incorrectly triggered auto-advance to the next track and started playback. The player now stays paused when the output device is changed.

### v3.20.0
- New: Focus Mode — single-window split view combining live preview and setlist. Access via ⌘⇧F or the Focus Mode toolbar button. A collapsible controls panel provides Force Poll, Override, Pause Display, and Last Tanda in one place.
- New: Hog Mode playback-interrupted alert — if another app claims the audio device during active playback, an alert appears with Retry and OK buttons to re-acquire exclusive access without navigating to Settings.

### v3.19.1
- Fix: Singer from Grouping field now correctly shown in the upcoming-track display during cortinas when using the Embrace player
- Fix: Grouping tag now shown in Setlist for tracks added before the Grouping feature was introduced (one-time metadata refresh on first launch)

### v3.19.0
- New: Grouping metadata field — read from Music.app, Swinsian, Embrace, J River, and audio file tags; optionally shown in setlist rows and selectable as the singer source on the dancer display
- New: Exclusive Mode (Hog Mode) for built-in player — claim exclusive access to the selected audio interface, with conflict detection and a Retry button
- Fix: Duplicate cortinas in setlist now tracked correctly by UUID
- Fix: Remaining set time and estimated end time account for auto-fade cortina effective play duration
- Fix: "Stop After Playing" can now target the currently playing track

### v3.18.4
- macOS Tahoe (26.x) compatibility: menu bar icon migrated from deprecated NSStatusItem to MenuBarExtra
- Sparkle updated to 2.9.2 for Tahoe update-alert compatibility

### v3.18.3
- Override Text (⌘⇧O) now has its own font and colour settings in Appearance
- When paused, pressing play again bypasses auto-gap and plays immediately
- Auto-gap calculation simplified: gap applied only when existing silence falls short
- Artwork tab: new artist entry auto-focuses the name field; remove button uses trash icon
- Setlist report: Played card shows played/total count; currently-playing track shown as played in setlist view

### v3.18.2
- Setlist player: unplayed tracks now appear in semibold with full-brightness text when genre colours are disabled, making them visually distinct from played tracks.
- Setlist player: Cortina tracks always display bold/bright regardless of genre colour rules, so tanda breaks are easy to spot.

### v3.18.1
- Fixed a crash when generating Setlist Reports on the installed app.

### v3.18.0
- **MegaSeg integration (Beta)** — TangoDisplay can now monitor MegaSeg Pro as a player source. Select MegaSeg in Settings › Player to enable. Genre is looked up from MegaSeg's own library database, with Music.app's iTunes Library as a fallback.
- **MegaSeg workflow notes:** The display updates only when a track starts on MegaSeg's program (main) output — the track that the audience hears. Pre-listening in the cue deck (headphones) never affects the display. Playlist look-ahead (upcoming tanda preview) is only available when playing from a loaded MegaSeg queue; ad-hoc plays from the library show no upcoming tracks. Tanda counting requires a loaded playlist. Requires MegaSeg v5.9.4 or later.
- **Please test and report results** — this integration is marked Beta because real-world DJ workflows with MegaSeg vary widely. If you use MegaSeg, please try it and report any issues.

### v3.17.0
- **Setlist Reports** — Export any setlist as a self-contained HTML report with genre breakdown charts, top-track ranking, per-tanda summaries, and an interactive searchable track table. Save reports from the Share menu in the Setlist tab; open, combine, and export from the new Reports tab in the sidebar.
- **Genre fallback for Music.app library** — Tracks whose genre is stored only in Music.app's iTunes Library.xml (not embedded in the audio file) are now correctly picked up by all genre-dependent features (cortina detection, genre colours, setlist stats).

### v3.16.7
- Built-in player renamed "Setlist (Built-In Player)" — appears first in the player list and is now the default for fresh installs, with a "Recommended" badge in Settings › Player
- Cortina denylist editor redesigned as a cleaner three-column layout (Genre | Display label | Controls)
- Setlist state (paused, queued, played) now persists to disk immediately
- Context menu now shows only relevant options depending on track state
- Removed unused "Last Tanda Label" colour setting from Appearance › Colours

### v3.16.6
- ⌘V paste now works with Foobar2000 — copy tracks with ⌘C in Foobar2000 and paste them directly into the Setlist panel

### v3.16.5
- Add tracks by pressing ⌘V — copy audio files in Finder, Music.app, or Swinsian with ⌘C, then press ⌘V while the Setlist panel is focused to append them instantly
- Genre colour now optionally extends to the song title — enable "Include song title" in Settings › Player › Genre Colours

### v3.16.4
- Playback progress bar moves into the currently-playing track row — elapsed time, remaining time, mark-as-played threshold, and auto-fade marker now appear directly on the row

### v3.16.3
- Add customisable genre tag colours to the Setlist player. Assign a colour to any genre keyword — keywords match case-insensitively and partially (e.g. "tango" matches "Argentine Tango"). Colours apply only to upcoming unplayed tracks; playing, paused, and already-played tracks keep their standard colours.

### v3.16.2
- Setlist status bar: added "Next cortina" countdown showing time until the next cortina
- Setlist status bar: added remaining track count alongside total playlist duration
- Setlist status bar: fixed "Ends at" time to correctly account for remaining time of the currently playing track

### v3.16.1
- Sparkle update dialog now shows a clean release notes summary instead of the full GitHub page
- Update dialog now appears automatically on launch when a new version is available

### v3.16.0
- Audio Unit Plugin support (Beta) — load any of the supported Apple AU effect plugins (EQ, dynamics, filters) directly into the audio chain
- Plugin picker filtered to restoration-relevant plugins only (AUNBandEQ, AUGraphicEQ, AUDynamicsProcessor, AUMultibandCompressor, AUPeakLimiter, AUHighShelfFilter, AULowShelfFilter, AUHipass, AULowpass)
- Quick-access plugin button in the Setlist toolbar — appears when a plugin is selected, opens the plugin window in one click
- Fixed: switching plugins no longer shows the previous plugin's editor window

### v3.15.4
- Add automatic update notifications via Sparkle — TangoDisplay now prompts you when a new version is available and can install it in one click

### v3.15.3
- **Fix (Built-In Player):** Year tag now reads correctly from AIFF files tagged with ID3v2.2 (the `TYE` frame used by older taggers and Swinsian imports) — previously this combination caused the year to appear blank.
- **Fix (Built-In Player):** Year tag now also reads correctly from files using the ID3v2.4 `TDRC` (Recording DateTime) frame, used by mp3tag and other modern taggers.

### v3.15.2
- **Fix (Built-In Player):** Resolved a crash that occurred when plugging in a USB audio interface (e.g. Focusrite Scarlett) — if the audio engine failed to restart after the device configuration change, playback was incorrectly attempted on the stopped engine.
- **Fix (Built-In Player):** Resolved a crash when switching the output device while audio was playing — the output device property is now set only after the engine is safely stopped, as CoreAudio requires.
- **Fix (Built-In Player):** Audio no longer redirects to a newly-plugged device (e.g. 3.5mm headphones) when a specific output is already chosen — the selected output is now re-asserted after any audio configuration change.

### v3.15.1
- **Fix (Built-In Player):** Resolved a crash (`EXC_CRASH`) that occurred when playing a track via Swinsian. When loading a new track, the audio engine fires a configuration-change notification asynchronously; the stale `tapInstalled` flag caused a second `installTapOnBus` call on an already-occupied bus, throwing an uncaught `NSException`. The tap is now always cleanly removed before reinstalling.

### v3.15.0
- **New (Built-In Player):** ReplayGain volume normalisation. Enable **ReplayGain** in **Settings › Player › ReplayGain** or via the new **ReplayGain** toolbar button (waveform icon) alongside EQ, Balance, and Auto-gap. Four modes: **Off**, **Track** (uses per-track RG tags), **Album** (uses album RG tags), and **Auto** (recommended — uses metadata when available; analyses the file against a configurable target loudness when absent). Controls include **Prevent clipping**, a **Preamp** slider (−12 to +6 dB), and a **Target Loudness** slider (−23 to −14 LUFS, active in Auto mode). Both the toolbar popover and Player Settings display a **Recommended** badge next to the Auto option. A live status line in the player controls shows the active gain (e.g. "Auto +2.3 dB · −18.0 LUFS") while a track is playing.

### v3.14.0
- **New (Appearance):** Artist Backgrounds. Add per-profile artist name → image mappings in **Appearance › Artwork & Motion**. When the playing track's artist contains a configured name (partial, case-insensitive, Unicode-safe match), the matching image is shown as the background instead of the profile background image. Falls back to profile background image, then background colour. Shared opacity, scale, horizontal, and vertical position controls. Active only while a dance track is playing — clears automatically on pause or stop.

### v3.13.0
- **Improvement (Control Window):** Sidebar navigation sections renamed — "Settings" is now "Global Settings" and "Profiles" is now "Profile Settings". The Appearance settings item has moved into the Profile Settings section, reflecting that appearance is per-profile.
- **Improvement (Profiles):** The profile list has been redesigned with improved layout — color swatches now appear at the leading edge of each row, the active profile is highlighted with a subtle accent-color background, and section headers use consistent styling.

### v3.12.0
- **New (Appearance):** Two new transition styles — **Push** (slides the new content in from the right as the old content exits left) and **Zoom** (new content scales up from small, old content scales out large). Both are available in **Appearance › Artwork & Motion › Transition › Style**.
- **Improvement (Control Window):** Status pane buttons (Force Poll, Override, Pause Display, Last Tanda) now display SF Symbol icons and expand to equal widths. Current track info is shown in a styled card. The control window minimum size is increased to 820 × 660.
- **Improvement (Preview Pane):** The preview in the control window now fills the available width at a fixed 16:9 aspect ratio, matching the display screen proportions more accurately.

### v3.11.1
- **Fix (Appearance Settings):** Track counter font changes in Appearance › Text now take effect on the display. Previously the font was hardcoded; only the colour setting was applied correctly.

### v3.11.0
- **Improvement (Appearance Settings):** Complete UI redesign — the Appearance settings panel is now organised into six tabs: **Visibility** (field visibility toggles and text order), **Text** (fonts), **Colours** (colour pickers), **Artwork & Motion** (transitions, artwork, and background image), **Cortina** (cortina display options), and **Last Tanda** (last tanda label settings). Each tab focuses on a single concern, making the panel significantly easier to navigate.
- **Improvement (Player Settings):** The Built-in Player settings section is now split into four named subsections — **Built-in Player**, **Cortinas**, **Playback**, and **Gap** — for clearer organisation.
- **Internal:** Removed unused `AppearanceProfile` properties and enums that had no effect on the display renderer.

### v3.10.0
- **Improvement (Built-In Player):** Auto-gap quick access. When auto-gap is enabled, a new **Auto-gap** button (timer icon) appears in the Setlist toolbar alongside EQ and Balance, opening a slider popover to adjust the gap duration instantly — no need to open Settings mid-performance. The button is disabled when auto-gap is off. The setlist footer now shows the live gap duration (e.g. "Auto-gap: 2.0s") instead of a plain "Auto-gap: on", updating in real time as you move the slider.
- **Confirmation:** Changing the gap duration while a track is playing takes effect for the very next gap. The duration is read at the moment the current track ends, so any adjustment made during playback applies to the upcoming silence preroll.

### v3.9.0
- **New: Last Tanda** — Signal the final tanda of your milonga to the audience. A **Last Tanda** toggle in the **Live** screen activates the label on both the cortina (coming-up section) and every dance track in the tanda — works with any player source. The label text, colour, and font are configured in **Appearance Settings › Last Tanda**; position is orderable in the **Text Order** drag list for both Dance Tracks and Cortinas — Coming Up. When using the Built-in Player, right-click any cortina in the setlist and select **Mark as Last Tanda** to pre-schedule activation — TangoDisplay activates the label automatically when that cortina starts and clears it when the next cortina begins. A red flag icon appears on the marked setlist row.

### v3.8.0
- **New (Built-In Player):** Auto-fade cortinas. Enable **Auto-fade all cortinas** in **Settings › Player › Built-in Player** to automatically fade out cortinas and advance to the next track after a configurable play time. An orange marker on the seek bar shows exactly when the fade will begin. Configure the play time with the **Cortina play time** slider (5–120 s); TangoDisplay adjusts automatically for short cortinas so the fade always completes before the track ends. Per-track override: right-click any cortina and select **Skip Auto-fade** to disable auto-fade for that track only — the fade buttons remain active for manual control. The option is hidden once fading has started. When auto-fade is active, the Fade & Stop and Fade & Continue buttons are disabled — the auto-fade handles the transition automatically. An orange dot and "Auto-fade: on" label appear in the setlist footer when the feature is enabled.

### v3.7.1
- **Fix (Built-In Player):** Tracks with audio running to the very end of the file no longer have their final second cut off. The completion callback now fires only after audio has been fully played back through the hardware output, so the player no longer discards the tail of a track that has no built-in trailing silence.

### v3.7.0
- **New: Track Info Transformations** — a new **Advanced** section in Settings lets you apply optional regex-based rules to how Artist, Title, Year, Album Artist, and Comments are displayed on the dancer screen — without modifying the original music tags. Each field has an independent enable toggle, a regex pattern field, a replacement template (supporting `$1`, `$2` capture groups), a live test-input field with instant result preview, and a per-field reset. A reset-all confirmation is available at the bottom of the panel. Transformations are applied in real time on both the dance-track and cortina views.

### v3.6.1
- **New (Built-In Player):** Export to M3U8. The Setlist toolbar's export button is now a **Share** menu. **Export to Apple Music** remains as before; a new **Export to M3U8…** option saves the full setlist as a standard M3U8 playlist file. A Save dialog lets you choose the destination; the default filename is `Tango Display SetList DDMMYY HH:MM.m3u8`. Use this to load your milonga setlist into any M3U-compatible player or DJ software.
- **Improvement (Built-In Player):** Level meter L/R channels now render as independent Canvas views with a fixed total width, removing the GeometryReader/PreferenceKey relay previously used to size the artwork panel.

### v3.6.0
- **New (Built-In Player):** Real-time stereo level meter. A dual-channel (L/R) bar-graph meter is now displayed in the player controls. Each channel shows RMS level with a green → yellow → red gradient, a peak-hold indicator that holds for 2 seconds then decays, and a dB scale (-0, -3, -6, -12, -24 dB). Peak markers turn red when clipping is detected; tap the meter to reset the clip indicator.
- **New (Built-In Player):** Stereo balance control. A **Balance** button in the Setlist toolbar opens a popover with a left/right balance slider. The readout shows "Centre", "L N%", or "R N%" at a glance; a **Centre** button resets to balanced. The setting persists across sessions.
- **Fix (Built-In Player):** Numeric ID3 genre tags (e.g. `(13)`, `(17)`, or plain `13`) are now resolved to their text names. Previously, tracks tagged with a numeric TCON value displayed the raw number as the genre on screen and in cortina detection.
- **Fix (Cortina Rules):** Partial genre matching now uses substring matching instead of prefix-only matching. A denylist entry for `Tango` will now catch `Non Tango Music` (word appears mid-string), not only `Tango Instrumental` (word at start). The tooltip in Cortina Settings is updated to reflect this.
- **New:** Help menu now includes **Tango Display Website** and **Facebook Group** links for quick access to support and community resources.

### v3.5.2
- **Improvement (Built-In Player):** Album artwork in the player controls is now displayed as a dedicated side panel sized to match the height of the playback controls, replacing the previous 70 pt corner overlay. When no track artwork is available a `SetlistLogo` placeholder fills the panel so the layout stays consistent.
- **Improvement (Built-In Player):** The seek bar is now a custom progress indicator (coloured fill, rounded corners) instead of a native `Slider`. The mark-as-played threshold marker is positioned accurately without the 10 pt inset workaround the native slider required.
- **Fix:** Quit confirmation is now handled once in `applicationShouldTerminate(_:)`, catching all quit paths — ⌘Q, the Dock menu, and the menu-bar Quit item — so the dialog can never be bypassed or shown twice.

### v3.5.1
- **Fix (Built-In Player):** The "next to play" highlight now correctly tracks the active entry while the player is running. Previously the `nextToPlayID` guard fell through when `isPlayerActive` was true, causing the indicator to point at the wrong track or disappear.
- **Fix (Built-In Player):** Already-played tracks can be reordered in the setlist again. Previously the drag handle was disabled for any track in the `.played` state; it is now disabled only for the currently `.playing` track.

### v3.5.0
- **New (Built-In Player):** Auto-gap. Enable **Auto-gap** in **Settings › Player › Built-in Player** to automatically pad the silence between tracks to a configurable minimum. TangoDisplay analyses the silence at the end of each finishing track and the start of the next, then schedules a silent preroll buffer so the combined gap always meets your target. Only silence is ever added — existing gaps that already meet the minimum are left untouched (a 1-second perceptibility buffer is still inserted so the separation is always audible). Three indicators show auto-gap state at a glance:
  - **Setlist footer dot** — a green dot and "Auto-gap: on" label appear in the setlist status bar when auto-gap is enabled; grey when disabled.
  - **Per-track wave icon** — a filled green wave icon on a track row means auto-gap silence was scheduled before that track; an outlined grey wave icon means auto-gap was skipped or ignored for that track.
  - **Settings** — **Minimum gap** slider (0.5–5 s, default 4 s); **Skip gap before first track** toggle (on by default) plays the opening track immediately with no silence preroll. Per-track overrides are available via right-click › **Ignore Auto-gap before this Track** / **Resume Auto-gap**.

### v3.4.0
- **New (Built-In Player):** Duplicate track protection. Enable **Duplicate track protection** in **Settings › Player › Built-in Player** to be warned before a track that already exists in the setlist is added. A native alert asks "Add anyway?" with **Add** and **Don't Add** buttons. A **Remember for this session** checkbox lets you lock in your choice — future duplicates are then added or skipped silently until the setlist is cleared, at which point the prompt reappears.

### v3.3.0
- **Fix (JRiver):** Artist tag now correctly shows the track Artist instead of Album Artist. Previously the poller substituted Album Artist into the Artist field whenever it was present, causing it to display as the Artist on screen.

### v3.2.0
- **New (JRiver):** Zone selection. DJs running multiple JRiver zones (e.g. Player + Prelistening) can now pin TangoDisplay to a specific zone. Go to **Settings › Player › Zone**, click **Refresh** to discover available zones, and select the one to monitor. The pre-listening zone is then ignored entirely. Defaults to *Active (follows current)* — no behaviour change for single-zone setups.

### v3.1.0
- **New: JRiver Media Center** is now a supported player source. Select **JRiver Media Center** in Settings › Player. TangoDisplay polls the MCWS HTTP API at `127.0.0.1:52199` every 2 seconds. Playlist look-ahead, tanda counting (Track N of M), coming-up cortina preview, album artwork, year, and singer/comment are all fully supported. JRiver must be running with Media Network enabled (Tools → Options → Media Network).
- **Fix (JRiver):** Year is now stable in the "Coming Up" cortina preview. Previously it flickered and triggered repeated screen transitions because the MCWS playlist endpoint omits year from its default field set, causing an oscillation between the enriched per-file metadata and the stripped playlist version.

### v3.0.4
- **Fix (Built-In Player):** Dragging a new track above the next-queued track now correctly promotes it as the next track to play. Previously, if Track A was stopped after the mark-as-played threshold (advancing the player to Track B as next), inserting a new Track E above Track B left the player locked on Track B. The setlist entries observer now detects when a reorder places a queued entry before the current queued-but-not-yet-loaded entry and promotes the earlier track automatically.

### v3.0.3
- **Fix (Built-In Player):** AIFF and Apple Lossless tracks no longer play silently when they are the first tracks in a setlist. The root cause was a channel-count mismatch: `AVAudioPlayerNode.scheduleFile` requires the file's format to exactly match the output bus channel count, but at startup the bus defaulted to stereo (2 ch). A mono AIFF (1 ch) mismatched this connection and produced silence with no error. Each time a track is loaded, the engine now stops, reconnects `playerNode → EQ → mixer` with the file's actual processing format, and restarts before scheduling — ensuring the bus always matches the file.

### v3.0.2
- **Fix (Built-In Player):** AIFF and Apple Lossless tracks no longer play silently when they are the first tracks in a setlist. Scheduling a PCM-format file triggers an `AVAudioEngineConfigurationChange` notification on AVAudioEngine's internal thread; the handler now dispatches to the main thread so it always runs after `isActivePlaying` is set, correctly rescheduling audio and resuming playback.

### v3.0.1
- **Fix (Built-In Player):** iTunNORM replay-gain tags are no longer shown as the singer/comment line. These tags are embedded by iTunes/Music.app as a hex string in the Comments field; the built-in player now strips them so they do not appear on the dancer screen.

### v3.0.0
- **New: Built-In Player** — TangoDisplay now includes a native audio player. No Music.app, Swinsian, or Embrace required. Build a setlist by dragging tracks from Finder, Music.app, or Swinsian; all display automation (cortina detection, tanda counting, coming-up preview, album artwork) works fully with the built-in player.
- **New: Setlist management** — drag-and-drop track queue with playback state tracking (queued / playing / paused / played), drag-to-reorder, context-menu bulk actions, Stop After Playing marker, and automatic setlist persistence across restarts.
- **New: Fade controls** — two one-click fade buttons: **Fade & Stop** (smooth fade to silence, then stop) and **Fade & Continue** (fade out, skip to next track, fade back in). Configurable fade duration (1–15 s, default 5 s). Ideal for cortina transitions.
- **New: Accidental-stop protection** — stopping playback requires two deliberate clicks (arm → confirm within ~3 s) to prevent mis-clicks mid-tanda.
- **New: 5-Band Equaliser** — ±12 dB per band (60 Hz low shelf, 250 Hz, 1 kHz, 4 kHz peaking, 12 kHz high shelf). Settings persist across sessions. One-click Flat reset.
- **New: Audio output routing** — choose any macOS output device (e.g. a DJ audio interface) from Player Settings. Falls back to system default if the selected device disconnects.
- **New: Track info toggles** — show or hide Year, Time, Comments, and Album Artist columns in setlist rows from Player Settings.
- **New: Export to Apple Music** — export the current setlist to a new Apple Music playlist with one click from the setlist toolbar.
- **New: Setlist footer** — live total duration and projected end time (e.g. "Ends ~23:45") calculated from remaining queued tracks.
- **New: Show Setlist menu item** — jump directly to the Setlist tab from the menu bar icon.

### v2.5.1
- **Fix (Cortina Rules):** Display label overrides now apply when a track genre matches a denylist entry via partial match (e.g. genre `Milonga (Alt)` with denylist entry `Milonga` + partial match on now correctly shows the label `Milonga` instead of the raw genre string).

### v2.5.0
- **New (Cortina Rules):** Display label override for denylist genres. Each denylist entry now has an optional label field. When filled in, the label is shown on the dancer screen instead of the raw genre tag — useful for libraries that use compound genre tags like `Tango: Vals` or `Tango: Milonga` but want cleaner on-screen text. Applies to both the dance-track view and the cortina "Coming Up" preview. Detection logic is unaffected.

### v2.4.0
- **New (Appearance):** Cortina track display. A new **Show cortina track during cortina** toggle in the Field Visibility section lets you display the playing cortina's own artist and/or title on the cortina screen. Two sub-toggles — **Cortina Artist** and **Cortina Title** — give independent control. Off by default; existing profiles migrate automatically.
- **New (Appearance):** Cortina track item order. A third sub-section — **Cortinas — Cortina Track** — in the Text Order section lets you reorder the Cortina Label, Cortina Artist, and Cortina Title items independently of the dance and "Coming Up" orderings.
- **New (Appearance):** Independent colors and fonts for five elements that were previously hardcoded: the Cortina label (was title font + artist color), the Next Up label (was genre font/color), Cortina Artist, Cortina Title, and the Idle message (was ultra-light artist color). Each has its own color swatch and font row in the Colors and Fonts sections.

### v2.3.0
- **New (Appearance):** Field Visibility. A new **Field Visibility** section in the Appearance tab provides independent show/hide toggles for every display field — Genre, Artist, Year, Title, Singer, and Artwork — with separate **Dance** and **Cortina** columns. This replaces the old global Show Year, Include Singer, and Show Singer During Cortina toggles. A **Show next track during cortina** toggle also lets you hide the entire "Coming Up" preview section during cortinas. Existing profiles migrate automatically — old toggle states are preserved as the starting values for the new per-type flags.

### v2.2.0
- **New (Appearance):** Text order is now configurable per profile. A new **Text Order** section in the Appearance tab lets you reorder the text items (Genre, Artist, Year, Title, Singer) using up/down buttons. There are two independent orderings — one for dance tracks and one for the cortina "Coming Up" preview — so the layouts can differ between the two contexts. Changes take effect on the dancer display immediately and are saved with the profile.

### v2.1.0
- **New (Appearance):** Singer source is now selectable. The **Include singer** toggle now shows a **Source** picker — **Comments** (reads the track's Comment metadata field, the original behaviour and default for existing users) or **Album Artist** (reads the Album Artist metadata field). Supported for Music.app, Swinsian, and Embrace.

### v2.0.1
- **Fix (Swinsian):** Track counter now increments correctly through a tanda (Track 1, Track 2, Track 3 …). Previously it was stuck at "Track 1" on every track because the playlist-membership guard always fired when no playlist data is available, resetting the track history on each track change.

### v2.0.0
- **New (Swinsian):** Swinsian now supports next-track look-ahead via the playback queue. The "Coming Up" next-tanda preview is now shown during cortinas when using Swinsian, bringing it to full parity with Music.app and Embrace for cortina previews.
- **New (Swinsian):** Track counter is now shown for Swinsian. It displays the position within the current tanda (e.g. "Track 2") using track history. The total (e.g. "of 4") remains unavailable — Swinsian's queue starts at the current track so backwards context is unavailable.
- **New:** Singer during cortina. Enable **Show singer during cortina** (in Appearance › Fonts, below the Singer row) to display the vocalist name in the cortina "Coming Up" preview. Requires **Include comments as singer** to also be enabled.
- **Improvement:** Track comments (singer names) are now fetched in bulk during playlist enumeration for Music.app and Embrace, so the vocalist line is available immediately on track change without a secondary async call.

### v1.9.0
- **New:** Singer/vocalist line. DJs who store the singer's name in the track's Comments field can now display it on the dancer screen, directly below the track title. Enable **Include comments as singer** in the Appearance tab › Fonts section. The singer line has its own font (family, size, bold, italic) and color controls, and is saved with your appearance profile. Supported for all three player sources — Music.app, Swinsian, and Embrace. For Swinsian, the comment is fetched via a short async AppleScript call when the notification doesn't include it.

### v1.8.0
- **New:** Update indicator in the sidebar. A small dot in the bottom-left corner of the sidebar shows your current version. It stays green when you're up to date, and turns red with a clickable link to the latest release when a newer version is available on GitHub. The check runs silently on launch and every hour; no action is taken if the device is offline.

### v1.7.0
- **New:** Album artwork is now shown on the dancer screen. Enable **Display album artwork** in the Appearance tab. Artwork is fetched from the current track for all three player sources (Music.app, Swinsian, and Embrace). Four controls — **Opacity**, **Scale**, **Horizontal offset**, and **Vertical offset** — let you position and blend it exactly as you want. Artwork fades in and out with track transitions.
- **Change:** The track counter is now hidden when the player is paused. When using Swinsian it showed only a position without a total — this was improved in v2.0.0.

### v1.6.0
- **New:** Year is now an optional display field. Enable **Show Year** in the Appearance tab to show the recording year on the dancer screen. Year has its own font and color controls. Supported for all three player sources — Music.app, Swinsian, and Embrace. Music.app and Embrace also show the next track's year in the cortina "Coming Up" preview.

### v1.5.0
- **Embrace — full Music.app parity:** Embrace now enumerates the full setlist via AppleScript, bringing it to full parity with Music.app. Tanda totals (e.g. Track 2 of 4) are now read directly from the playlist, and the "Coming Up" cortina preview correctly skips any queued cortinas to show the first dance track of the next tanda.

### v1.4.0
- **New (Embrace):** Embrace now supports next-track look-ahead via AppleScript — the "Coming Up" upcoming tanda preview is shown during cortinas.

### v1.3.1
- **Reliability:** Music.app now subscribes to the `com.apple.Music.playerInfo` DistributedNotification, triggering an immediate poll on every track and state change — mirroring how Embrace support works. This eliminates detection delays that could occur when the watchdog had backed off the polling interval due to transient AppleScript failures. The 2-second fallback polling and watchdog backoff are unchanged.

### v1.3.0
- **Fix:** Unpausing the display no longer leaves it frozen when the player state changed while the display was paused. The dedup guard is now reset on unpause and an immediate poll is triggered, so the display snaps to the real current player state without waiting for the next scheduled poll.
- **Fix:** Pressing "Pause Display" while the player is paused (not the display) no longer silently engages user-level display-freeze, causing the display to stay stuck when music resumes.
- **Fix:** Player stop now clears the user-pause flag, so restarting music after a stop always updates the display correctly.
- **New:** Status bar now shows two independent badges — **player state** (Playing / Player Paused / Idle) and **display state** (Display Live / Display Paused / Cortina / Override) — so the state of each is always visible at a glance.

### v1.2.0
- **New:** Embrace is now supported as a player source. Select Music.app, Swinsian, or Embrace in **Settings › Player**. Embrace uses a hybrid push/poll strategy — real-time notifications plus AppleScript polling for reliability. Note: playlist lookahead and the "Coming Up" preview during cortinas are unavailable with Embrace — tanda counting falls back to track history.

### v1.1.0
- **New:** Swinsian is now supported as an alternative player source. Select Music.app or Swinsian in **Settings › Player**. Swinsian uses real-time push notifications instead of polling. Note: playlist lookahead and the "Coming Up" next-tanda preview during cortinas are unavailable with Swinsian — tanda counting falls back to track history.

### v1.0.3
- **Fix:** Display labels ("CORTINA", "COMING UP", idle message) now update immediately on the presentation window when saved, instead of requiring a restart. Edited via the Display tab with a **Save** button and an unsaved-changes indicator.

### v1.0.2
- **Bug fix:** "Coming Up" next-tanda artist on the cortina screen now refreshes on every cortina transition instead of waiting up to 20 seconds. If the user switches playlists while a cortina is playing, the stale next-artist preview is cleared immediately when the fresh playlist data arrives, falling back to a plain "CORTINA" display.

### v1.0.1
- **Bug fix:** Clearing an override no longer inherits a user-pause that was active before the override was triggered. `isPausedByUser` and `pendingStateBeforePause` are now reset in `clearOverride()`.

### v1.0
- Initial release.

---

## Credits

The **Shellac Restoration** filters (Declick and Dehum) are the portable DSP cores from
[ShellacFilters](https://github.com/shaforostoff/shellacfilters) by Nick Shaforostov — MIT, itself built on
the [Airwindows](https://www.airwindows.com) framework by Chris Johnson. The cores live verbatim in
[`Sources/TangoDisplayObjC/shellac/`](Sources/TangoDisplayObjC/shellac/); the Audio Unit wrapper around them
is adapted from [EmbraceNG](https://github.com/shaforostoff/EmbraceNG)'s `RestorationAudioUnit.mm`
(© 2024 Ricci Adams, MIT / 1-clause BSD).

---

## License

MIT — see [LICENSE](LICENSE).
