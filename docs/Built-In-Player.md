# Built-In Player

TangoDisplay includes a native audio player that lets you manage and play your milonga setlist directly — no Music.app, Swinsian, or Embrace required. All display automation (cortina detection, tanda counting, coming-up preview, album artwork) works fully with the built-in player.

> **Screenshot placeholder:** feature banner — full setlist view with tracks loaded

---

## Enabling the Built-in Player

1. Click the display icon in the menu bar › **Show Settings Window**
2. Go to **Player** in the sidebar
3. Under **Player Source**, select **Setlist (Built-In Player)** — it appears at the top of the list, marked **Recommended**
4. Switch to the **Setlist** tab to build your setlist

Once the built-in player is active, you can jump straight to the Setlist tab at any time from the menu bar: click the display icon › **Show Setlist**.

> **Screenshot placeholder:** Player Settings view with Setlist (Built-In Player) selected

---

## The Setlist Tab

The Setlist tab is the main workspace for the built-in player. It shows your full track queue, player controls at the top, and setlist statistics at the bottom.

### Adding Tracks

Drag tracks directly from:

- **Music.app** — drag from the track list or search results
- **Swinsian** — drag from the browser
- **Finder** — drag audio files from anywhere on your filesystem

Drop onto the track list or into the empty drop zone when the list is empty. Dropped rows appear instantly with their filename and fill in full metadata (read from the audio file itself) a moment later — they do not need to be in any library. Cloud-only Music.app tracks are downloaded on drop, so a mixed selection of downloaded and cloud-only tracks is added in full rather than partially.

To insert mid-list, drag onto a specific row to place the new track before it rather than appending to the bottom.

If a dropped file no longer exists on disk (for example a Music track shown with a warning triangle because its underlying file is missing), it is rejected on drop with a brief *N files not found* note rather than being silently skipped later at playback.

When the built-in player is active, dropping tracks from Music also imports each track's **start/stop times** (set in Music under Song Info → Options) as playback trim markers automatically — see [Track Start & End Time](#track-start--end-time) below. The times are re-read from Music on every drop, so an adjustment you make in Music takes effect on the next track you drag across, with no need to restart TangoDisplay.

You can also **copy** audio files in Finder, Music.app, Swinsian, or Foobar2000 (⌘C), then press **⌘V** while the Setlist panel is focused to append them instantly — no drag required.

**Supported formats:** MP3, M4A (AAC), AIFF, WAV, FLAC, CAF, Opus.

#### Duplicate Track Protection

When **Duplicate track protection** is enabled in **Player Settings**, dropping one or more tracks already in the setlist (played or unplayed) shows an alert. The wording reflects how many duplicates were dropped and whether they have already been played, e.g.:

> *This track already exists in this set. Add anyway?*
> *3 tracks have already been played in this set. Add anyway?*

- **Add** — adds the duplicate(s).
- **Don't Add** — skips them.
- **Remember for this session** — check this before clicking either button to lock in your choice. Subsequent duplicates are then added or skipped silently for the rest of the session. The remembered choice is cleared when you click **Clear Setlist**.

When duplicates are skipped silently (because of a remembered choice or the **Don't Add** button), a brief note appears at the bottom of the list — e.g. *Added 4 — 2 already in set* — so the skipped tracks aren't mistaken for a failed drag.

Non-duplicate tracks in the same drag operation are always added immediately, regardless of this setting.

> **Screenshot placeholder:** setlist view with several tracks showing mixed state (queued, playing, played)

### Track Rows

Each row shows:

| Element | Details |
|---|---|
| State icon | Waveform = playing · Pause = paused/armed · Checkmark = played · Play = next up |
| Title & Artist | Extracted from the audio file's tags |
| Genre tag | Colour-coded: green = playing, orange = paused, blue = next to play, grey = queued/played. Custom colours can be assigned to upcoming tracks by genre keyword (see Genre Colours below). |
| Year | Optional — toggle in Player Settings |
| Duration | Optional — toggle in Player Settings |
| Comments / Album Artist | Optional — toggle in Player Settings |
| Stop marker | Small stop icon when "Stop After This Track" is set |
| Repeat icon | Blue repeat icon when the track is set to Repeat |
| Auto-gap icon | Filled green wave = auto-gap silence applied before this track · Outlined grey wave = skipped or ignored |
| Last Tanda flag | Red flag icon = this cortina is marked as the last tanda and will activate the Last Tanda label when it plays |
| Tag colour dot | Coloured dot on the left edge of the row when a tag colour has been assigned (see [Track Tags](#track-tags) below) |
| Performance badge | Small indicator when the track is marked as a performance track |
| Progress bar | Appears beneath the currently-playing row: shows elapsed position, remaining time, the mark-as-played threshold marker, and the auto-fade marker (for cortinas when Auto-fade is enabled) |

The setlist persists across app restarts — it is saved automatically to Application Support.

---

## Player Controls

The player controls sit above the track list.

> **Screenshot placeholder:** player controls area showing level meter, transport, seek bar, fade buttons, volume, eye button, and artwork

The controls are arranged in three columns with a volume row below:

- **Level meter** — dual-channel (L/R) bar graph on the left side of the controls panel. Gradient bars show real-time RMS level from green (quiet) through yellow to red (loud). White peak-hold markers latch for 2 seconds then decay; they turn red when clipping is detected. Tap the meter to reset clip indicators. A dB scale (-0, -3, -6, -12, -24) runs alongside.
- **Eye button** — scrolls the track list to highlight the currently playing track
- **Track info** — title and artist of the current track
- **Transport button** — large central play/stop button (see states below)
- **Fade buttons** — Fade & Stop and Fade & Continue (see below)
- **Volume slider** — master volume for the built-in player (0–100%)
- **Artwork panel** — current track artwork, sized to match the height of the controls column. Falls back to the SetlistLogo placeholder when no artwork is embedded in the file.

### Transport Button States

| Colour | State | Click to… |
|---|---|---|
| Green (play icon) | Stopped / ready | Start playback |
| Accent (waveform) | Playing | Arm stop |
| Orange (pause icon) | Armed — stop pending | Confirm stop |
| Red (stop icon) | Stopped after confirm | Resume or start next |

### Accidental Stop Protection

Stopping playback requires two deliberate clicks to prevent mis-clicks mid-tanda:

1. **First click** while playing → button turns orange, entering an "armed" state for approximately 3 seconds
2. **Second click** within that window → playback stops
3. **No second click** → the armed state expires and playback continues uninterrupted

This means a single accidental tap on the transport never kills the music.

### Fade Buttons (Cortina Controls)

The two fade buttons are enabled only when the currently playing track is a recognised cortina — they are never active on dance tracks. Use them when you want to end a cortina early rather than letting it play to its natural finish:

| Button | What it does |
|---|---|
| **Fade & Stop** | Smoothly fades the cortina volume to zero over the configured duration, then stops. |
| **Fade & Continue** | Smoothly fades the cortina volume to zero, then immediately advances to the next track and restores volume. |

Both buttons are disabled while a fade is already in progress. The fade uses an exponential curve for a natural, professional sound.

Configure the fade duration in **Player Settings › Cortina fade** (1–15 seconds).

When **Auto-fade all cortinas** is enabled, the fade buttons are automatically disabled while a cortina is playing — the auto-fade will handle the transition at the configured time. Right-click the cortina in the setlist and select **Skip Auto-fade** to re-enable manual control for that track.

---

## Managing Your Setlist

### Re-ordering Tracks

Drag rows up or down to reorder. Tracks that have already been played are locked in place and cannot be moved — only queued (unplayed) and paused tracks are draggable. This prevents accidentally scrambling your played history.

If you pause a track and then drag a queued track above it, pressing play starts the new topmost track — playback always begins from the highest not-yet-played row, and the paused track reverts to a normal queued track.

### Context Menu Actions

Right-click any row:

| Action | What it does |
|---|---|
| **Mark as Played** | Stamps a queued track as played without playing it |
| **Mark as Not Played** | Resets a played track to queued so it will play again |
| **Stop after Playing** | Sets a stop marker — playback halts automatically when this track finishes. Can also be set on the currently playing track. Shows as **Resume after Playing** when already set; click again to clear it. Setting it clears any Repeat on the same track. |
| **Repeat Track** | Loops a non-dance track — it replays continuously until you clear the repeat or it hits a stop-after marker. A blue repeat icon appears on the row. Shows as **Stop Repeating** when already set. Mutually exclusive with Stop after Playing (marking Repeat on a stop-after track prompts to switch). Any fade action (Fade & Stop, Fade & Continue, auto-fade) clears the repeat. |
| **Track Start & End Time…** | Opens an editor to trim playback to a sub-range of the track, so you can replay it from a mid-point (e.g. during applause after a performance). Works on any track. Shows a blue start–end badge on the row once set, and **Clear Start & End Time** to remove it. See [Track Start & End Time](#track-start--end-time) below. Built-in player only. |
| **Delete** | Removes the track from the setlist (asks for confirmation) |
| **Ignore Auto-gap before this Track** | Disables auto-gap for this track only. Shows as **Resume Auto-gap** when already set; click again to re-enable it. |
| **Skip Auto-fade** | Disables auto-fade for this cortina track only, re-enabling the Fade & Stop and Fade & Continue buttons for manual control. Available only when Auto-fade is enabled and fading has not yet started. |
| **Mark as Last Tanda** | Marks this cortina as the last tanda. TangoDisplay will automatically activate the Last Tanda label when this cortina starts and deactivate it when the next cortina begins. A red flag appears on the row. Shows as **Remove Last Tanda** when already set. Available only on cortina tracks. Requires Last Tanda label text to be configured in Appearance Settings. |
| **Edit Upcoming Info…** | Opens an editor for the artist, singer and year shown in the "Coming Up" preview during this cortina — for mixed tandas whose first track would misdescribe what's next. A pencil icon appears on the row once set. Shows **Clear Upcoming Info** alongside when already set. Available only on cortina tracks that have not finished playing. See [Edit Upcoming Info](#edit-upcoming-info) below. |
| **Mark as Performance** | Marks this track as a guest performance track. When it plays, the dancer display switches to the custom Performance view instead of normal track info. Shows as **Remove Performance** when already set. See [Performance Tracks](#performance-tracks) below. |
| **Tag Colour** | Opens a sub-menu to assign a colour dot (red, orange, yellow, green, blue, purple) to the row for visual organisation, or **Clear Tag Colour** to remove it. See [Track Tags](#track-tags) below. |
| **Reload Track Info** | Re-reads the artist, title, genre, year and other tags from the file. Use it when a row shows a filename instead of proper track details — see [Tracks Showing Filenames](#tracks-showing-filenames) below. Select several rows first and the action becomes **Reload Track Info for Selection**. |

> **Screenshot placeholder:** right-click context menu on a setlist row

### Tracks Showing Filenames

TangoDisplay reads a track's tags from the file at the moment you drop it into the setlist. If the file is on an external drive that is asleep, or on a slow or network volume, that read can come back empty — the row then keeps the filename as its title and shows no artist or genre, both in the setlist and on the dancer display.

Right-click the affected rows and choose **Reload Track Info** to read the tags again. Rows that never got a successful read are also retried automatically each time TangoDisplay launches.

> **Worth knowing:** a track with no genre is treated as a cortina under the deny-list rule, because an empty genre is not in your list of dance genres. A failed tag read can therefore throw off tanda counting and the "Coming Up" preview until you reload the track info. Waking an external drive before you build the setlist avoids the problem entirely.

**Bulk mark:** ⌘-click or Shift-click to select multiple rows, then right-click to apply **Mark as Played** or **Mark as Not Played** to all selected tracks at once. When two or more tracks are selected, the status bar at the bottom of the setlist shows the number of selected tracks and their combined duration.

### Stop After Playing

When **Stop after Playing** is set on a row, a small stop icon appears in that row and playback halts automatically when that track completes. Right-click the same row again and select **Resume after Playing** to clear the marker. Only one stop marker can be active at a time.

### Clearing the Setlist

Click the **Clear Setlist** button in the toolbar. This removes all tracks and resets all playback state.

### Hiding Played Tracks

Click the **filter button** (three-line funnel icon) in the Setlist toolbar to hide all fully-played tracks. The current or next-to-play track is always visible — it won't disappear even if it has been early-marked as played. The list scrolls to the active track automatically when you toggle the filter.

While the filter is active, a banner at the top of the list shows how many played tracks are currently hidden.

Click the button again to restore the full track list and scroll the current track back into view.

The hide-played setting is remembered across sessions.

---

## Setlist Footer

A status bar at the bottom of the track list shows:

> **Screenshot placeholder:** setlist footer showing total duration and estimated end time

- **Total duration & remaining count** — the combined length of all tracks followed by the number of unplayed tracks (e.g. "1h 42m · 28 remaining")
- **Next cortina** — a live countdown showing how much time remains before the next cortina begins, based on the current elapsed position and queued track durations. Shows "0s" when a cortina is already playing.
- **Estimated end time** — a projected clock time when the setlist will finish, calculated from the current elapsed position, all remaining queued tracks, and any stop-after marker (e.g. "Ends ~23:45"). For cortinas with Auto-fade enabled, the effective play duration (play time + fade duration) is used rather than the full track length, so the estimate stays accurate when cortinas fade early.

Clicking anywhere on the timing area opens the **Set Timings** window — a large-format floating dashboard displaying total set time, remaining track count, next cortina countdown, estimated end time, and a current-track progress bar. The window can be left open on a secondary display for at-a-glance monitoring during a milonga.
- **Auto-gap status** — when auto-gap is enabled, a small green dot and the live gap duration (e.g. "Auto-gap: 2.0s") appear. The dot turns grey and the label reads "Auto-gap: off" when the feature is disabled. The duration updates in real time as you adjust the slider.
- **Auto-fade status** — when auto-fade is enabled, a small orange dot and "Auto-fade: on" label appear alongside the auto-gap indicator. The dot turns grey and the label reads "Auto-fade: off" when the feature is disabled.

---

## Auto-Gap

Auto-gap analyses the silence at track boundaries and schedules a silent preroll buffer before each track so the gap between songs always meets your target minimum — useful for tango DJs who want consistent, perceptible separations between tandas without adding unnecessary dead air.

> **How it works:** TangoDisplay reads the audio waveform at the end of the finishing track and the start of the incoming track, measures the existing silence, then prepends exactly as much extra silence as needed. Only silence is ever added — it never shortens a gap. If the existing silence already meets the minimum, a 1-second buffer is still inserted so the separation is always audible.

### Enabling Auto-Gap

1. Go to **Settings › Player**
2. Under **Built-in Player**, enable the **Auto-gap** toggle
3. Use the **Minimum gap** slider to set your target (0.5–5 s; default 4 s)

### Skip Gap Before First Track

When **Skip gap before first track** is enabled (the default), the opening track of the setlist starts immediately with no silence preroll — the gap only applies between consecutive tracks. Disable this if you want the same treatment from the very first song.

### Skip Gap After Manual Stop

When **Skip gap after manual stop** is enabled, stopping a track before it ends means the next track you start plays immediately with no silence preroll — the break while you were between tracks already provided the gap. This covers the transport stop button and Fade & Stop. Off by default.

Stopping a track and then resuming that same track does not count: when it later ends normally, the following track gets its usual auto-gap.

### Per-Track Override

Right-click any queued track row and select **Ignore Auto-gap before this Track** to exempt that individual track. The option becomes **Resume Auto-gap** when already set; click it again to re-enable. This lets you keep auto-gap active globally while skipping it for specific tracks (e.g. a track you want to follow immediately after its predecessor).

The override reflects the track's *effective* state, so it works even on the first track: when **Skip gap before first track** is auto-applying the skip, the option reads **Resume Auto-gap** and selecting it forces the gap back on for that track.

### Pausing and Resuming

When you pause and then press play again, the player resumes without applying the auto-gap — the next track begins immediately. Auto-gap only applies during normal end-of-track transitions.

### Reading the Indicators

Three places in the UI reflect auto-gap state:

| Indicator | What it means |
|---|---|
| **Setlist footer dot** | Green dot + "Auto-gap: 4.0s" (live duration) = feature active. Grey dot + "Auto-gap: off" = feature disabled. |
| **Timer toolbar button** | Opens the Auto-gap popover for instant duration changes. Disabled when auto-gap is off. |
| **Filled green wave icon** on a track row | Auto-gap silence was successfully scheduled before this track |
| **Outlined grey wave icon** on a track row | Auto-gap was skipped or ignored for this track (first track with "Skip gap before first track" on, or per-track override active). A skip caused by "Skip gap after manual stop" is not shown here — that decision is only made at the moment the next track starts. |
| *(no icon)* | Auto-gap not applicable to this track |

---

## Auto-Fade Cortinas

Auto-fade automatically fades out a cortina and advances to the next track after a configurable play time — useful when you want cortinas to end cleanly without manual intervention.

### Enabling Auto-Fade

1. Go to **Settings › Player**
2. Under **Built-in Player**, enable the **Auto-fade all cortinas** toggle
3. Use the **Cortina play time** slider to set how many seconds of the cortina should play before the fade begins (5–120 s; default 30 s)

When a cortina starts, an orange marker appears on the in-row progress bar to show exactly when the fade will trigger.

> **Short cortinas:** If a cortina is shorter than the play time plus the fade duration, TangoDisplay adjusts automatically — the fade starts early enough to complete before the track ends.

### Fade Buttons and Auto-Fade

When auto-fade is enabled for a cortina, the **Fade & Stop** and **Fade & Continue** buttons in the player controls are disabled — the auto-fade will handle the transition at the right moment. Once the fade begins, it cannot be interrupted.

### Per-Track Override

Right-click any cortina row in the setlist and select **Skip Auto-fade** to disable auto-fade for that track only. The orange progress-bar marker disappears and the fade buttons become active for manual control. The option is hidden once the fade has already started.

### Reading the Indicators

| Indicator | What it means |
|---|---|
| **Orange marker on progress bar** | The point at which auto-fade will begin for the current cortina (visible in the in-row progress bar beneath the playing track) |
| **Setlist footer orange dot** | Orange dot + "Auto-fade: on" = feature active. Grey dot + "Auto-fade: off" = feature disabled. |
| **Fade buttons (disabled)** | Auto-fade is scheduled — the transition will happen automatically |

---

## Cortina Volume Reduction

Cortinas often sit louder than the dance tracks around them — sometimes by design, sometimes because ReplayGain alone doesn't bring the level down enough for a milonga floor. The **Cortina volume** slider lets you pull every detected cortina down by a fixed amount in dB without touching the source files or affecting dance tracks.

### Enabling

1. Go to **Settings › Player**
2. Under **Cortinas**, move the **Cortina volume** slider
3. Range: **-10 dB to 0 dB** in 0.5 dB steps. Default **0 dB** (off).

The reduction is applied **on top of ReplayGain** — if ReplayGain is on, the cortina's per-track gain is calculated first and the slider's reduction is multiplied in after. A track is treated as a cortina if it matches the same cortina-detection rules used elsewhere in TangoDisplay (configured in **Settings › Cortina Rules**).

Changes apply live: move the slider while a cortina is playing and the level updates immediately.

---

## Last Tanda

Pre-schedule which cortina is the last tanda of your milonga. When that cortina plays, TangoDisplay automatically activates the Last Tanda label on the dancer display — no manual intervention needed mid-set.

### Marking a Cortina

Right-click any cortina row in the setlist and select **Mark as Last Tanda**. A red flag icon appears on the row to confirm. Only one cortina can be marked at a time — marking a new one automatically clears any previous marker.

> If no Last Tanda label text is configured in **Appearance Settings › Last Tanda**, a warning is shown instead of marking the cortina. Configure the label text first.

### How Activation Works

| Moment | What happens |
|---|---|
| Marked cortina starts playing | Last Tanda label activates automatically |
| During dance tracks in the tanda | Label remains visible on every track |
| Next cortina starts | Label deactivates automatically |

### Live Override

The **Last Tanda** toggle on the **Live** screen always takes priority. You can turn it off at any time — the label clears immediately and remains off for the rest of the current tanda, even as new tracks play.

### Removing the Marker

Right-click the marked cortina row and select **Remove Last Tanda**. The flag icon disappears.

---

## Edit Upcoming Info

During a cortina the display previews the next tanda using the metadata of that tanda's **first dance track**. For a mixed tanda — several orchestras, several singers, a spread of years — those details describe one track, not the tanda. Edit Upcoming Info replaces them with text you type, for that cortina only.

### Setting the Text

Right-click a cortina row and select **Edit Upcoming Info…**. The editor offers three fields:

| Field | Notes |
|---|---|
| **Artist** | Free text, e.g. `Mixed Tanda` or `Di Sarli / Troilo` |
| **Singer** | Shown only when the singer field is enabled for cortinas in Appearance settings |
| **Year** | Free text, so ranges and labels work: `1941-43`, `Golden Age` |

Each field's placeholder shows what the display would use unedited. Leave a field blank to keep the real metadata for that field — the three are independent. **Save** applies the text; **Clear All** empties all three and removes the override.

A pencil icon appears on the row while an override is set. To remove it later, right-click the row and choose **Clear Upcoming Info**.

### How It Is Shown

- The text is shown **verbatim** — the uppercase/lowercase transforms in Settings are not applied, so what you type is what dancers see.
- It replaces the corresponding built-in Coming Up fields, and the `{ARTIST}`, `{SINGER}` and `{YEAR}` placeholders in any custom text lines shown during the cortina.
- Editing the cortina that is **already playing** updates the dancer display immediately.
- The override is saved with the setlist and survives restarts. It belongs to that one cortina row; other cortinas are unaffected.
- Built-in player only — external players have no per-entry setlist metadata.

---

## Stereo Balance

Click the **Balance** button (dial icon) in the Setlist toolbar to open the balance popover.

- Drag the slider left to shift audio towards the left channel, or right to shift it towards the right.
- The readout above the slider shows **Centre**, **L N%**, or **R N%** depending on the current position.
- Click **Centre** to snap back to balanced (0).

The balance setting persists across app restarts. The Balance button is disabled when the built-in player is not active.

---

## Auto-Gap Quick Access

When auto-gap is enabled, a **timer icon button** appears in the Setlist toolbar alongside EQ and Balance. Click it to open a popover with a duration slider — the same 0.5–5 s range as the full Settings panel, but reachable in one click during a performance.

The button is **disabled** when auto-gap is off (enable it first in **Settings › Player › Auto-gap**).

### Changing the gap mid-performance

You can adjust the duration while a track is playing. The new value takes effect for the very next gap: the gap duration is read at the moment the current track ends, so any change you make during playback applies to the upcoming silence preroll. The setlist footer updates to reflect the new value in real time.

> **Example:** Global gap is 4 s. While Track A plays, open the popover and drag to 2 s. The gap before Track B will be 2 s. Drag back to 4 s before Track C ends and subsequent gaps return to 4 s.

---

## Waveform Window

Click the **Waveform button** (waveform path icon) in the Setlist toolbar to open a compact floating window showing the audio waveform of the current or upcoming track.

The window displays:

- **Waveform bars** — amplitude of the audio across the full track duration. Bars before the playhead are shown in the accent colour; bars after the playhead are dimmed.
- **Playhead** — a red line that moves in real time to show elapsed position.
- **Elapsed / total time** — shown at the left and right of the waveform.

Waveform data is computed from the audio file on demand and cached so subsequent plays load instantly. The button is enabled whenever tracks are loaded in the setlist.

---

## Track Start & End Time

Sometimes you want to replay a track from part-way through — for example while a performing couple take an applause. **Track Start & End Time** lets you trim any track (dance or cortina) to a sub-range so playback starts and stops where you choose.

Right-click a row and select **Track Start & End Time…** to open the editor window. It shows the track's waveform with two controls for setting the range:

- **Drag the handles** — a green handle at the start and a red handle at the end of the waveform. The part of the waveform outside your selection is dulled so the chosen range stands out.
- **Type the times** — enter a **Start** and **End** time manually in `m:ss.d` format (tenths of a second are supported, e.g. `1:05.4`). The end time cannot be earlier than the start.

Click **Apply** to save (or **Cancel** to discard). The row then shows a blue **start–end** badge. To remove the trim, right-click the row and choose **Clear Start & End Time**.

Notes:

- Playback begins at the start time and stops at the end time, then advances as normal.
- Combine with **Repeat Track** to loop just the trimmed range continuously.
- This is enforced by the built-in player only, so the menu action appears when the built-in player is the active source.
- Tracks dropped from Music while the built-in player is active have their start/stop times (Song Info → Options) imported as trim markers automatically, so you don't need to re-enter them here. You can still adjust or clear them afterwards. The times are read fresh on each drop, so you can set them in Music and drag the track straight across.

---

## Track Tags

Assign a colour tag to any track for visual organisation of your setlist. Right-click a row and choose **Tag Colour**, then pick from:

**Red · Orange · Yellow · Green · Blue · Purple**

A coloured dot appears on the left edge of the row. To remove it, right-click and choose **Clear Tag Colour**.

Tags persist in the saved setlist — they survive app restarts and reload with the setlist. They have no effect on playback.

---

## Performance Tracks

Mark a track as a **performance track** when a guest couple or performer will dance to it and you want the audience display to show something other than the normal track info.

### Marking a Track

Right-click any track and choose **Mark as Performance**. A small indicator appears on the row. Right-click again and choose **Remove Performance** to clear it.

### What Happens on the Display

When a performance track begins playing, the dancer display switches to the **Performance view** — a custom layout with a dedicated background image and DJ-configured text lines. The normal artist/title/genre display is hidden.

Configure the Performance view in **Appearance Settings › Performance**:

- **Background image** — a separate image shown only during performance tracks (independent of your profile's background image). An optional **Show during cortina** toggle also shows this background during the cortina that immediately precedes the performance.
- **Text lines** — add up to any number of text lines, each with its own font, size, and colour. Text can include placeholders: `{title}`, `{artist}`, `{genre}`, `{year}` — replaced with the playing track's metadata at runtime. Each line has its own **Show during cortina** toggle to pre-announce the performance on the cortina screen.

### Auto-Stop After Performance

In **Settings › Player › Performance**, the **Stop after each performance track** toggle (on by default) automatically stops playback when a performance track finishes — giving you time to re-cue for the next performer before the music resumes.

---

## Exporting the Setlist

Click the **Share** button (↑ icon) in the Setlist toolbar to open the export menu. The button is disabled when the setlist is empty.

### Export to Apple Music

Creates a new Apple Music playlist containing all tracks in the current setlist. The playlist is named with the current date and time.

> **Note:** Export to Apple Music requires the **Automation › Music** permission. macOS will prompt for this on first use.

### Export to M3U8…

Opens a Save dialog and writes a standard M3U8 playlist file. Each track is written as an `#EXTINF:` line (with duration and `Artist — Title` metadata) followed by the absolute file path. The default filename is `Tango Display SetList DDMMYY HH:MM.m3u8`.

Use this to import your milonga setlist into any M3U-compatible player or DJ software.

### Save Setlist Report…

Saves a snapshot of the current setlist as a named report. The report captures every track's title, artist, genre, year, duration, play state, and last-tanda flag. Reports are stored in Application Support and are visible in the **Reports** tab, where they can be exported as interactive HTML files.

---

## Shellac Restoration

Click the **Restoration** button (sparkles icon) in the Setlist toolbar to open the restoration popover. It hosts two filters aimed squarely at 78 rpm transfers, and they run **before** the equaliser — the record is repaired first, then shaped.

Like the ReplayGain button, Restoration is **never disabled** — you can set it up while building the setlist, before playback has started.

Both come from [ShellacFilters](https://github.com/shaforostoff/shellacfilters) by Nick Shaforostov (MIT), trained on shellac transfers including those from tangotunes.com and tangotimetravel.be. The DSP cores are built on the [Airwindows](https://www.airwindows.com) framework by Chris Johnson, and the Audio Unit wrapper TangoDisplay runs them in is adapted from [EmbraceNG](https://github.com/shaforostoff/EmbraceNG)'s `RestorationAudioUnit.mm` (© 2024 Ricci Adams, MIT / 1-clause BSD).

> **Screenshot placeholder:** Restoration popover with Declick and Dehum sections

**Restoration is off by default.** Nothing about playback changes until you switch it on.

### Declick

Removes the clicks and pops of surface wear. It fits a predictive model to each block of audio, spots clicks as the samples that model cannot explain, and reconstructs what the waveform should have been — rather than smoothing over what is there.

| Control | What it does |
|---|---|
| **Sensitivity** | How readily a sample is called a click. The default puts the trigger at 3.9 sigma above the local noise estimate; on 78 rpm tango transfers that takes impulsive events from roughly 71 per second down to 14. |
| **Extent** | How far each detection spreads into the tail of the click. |
| **Max repair** | The longest stretch that may be reconstructed. Damage longer than this is left alone rather than guessed at. |
| **Repair depth** | How much of the estimated click is subtracted. 0 is the setting measured to add the least error of its own; raising it removes more of each click but substitutes more guesswork. |
| **Passes** | How many times the detector sweeps each block. A second pass catches clicks the first pass's repairs uncover. |
| **Model order** | Taps in the predictive model — the lever that pays most, and the one that costs most CPU. The default stops at 64. |
| **Dry/Wet** | Blend against the original. 0 passes the input through untouched, for A/B. |

Declick adds about **18 ms of latency** while it is engaged — inaudible in the room, and below the resolution of every timing feature in the app. Note that Dry/Wet at 0 still runs the filter, so that A/B lines up sample for sample; to stop paying the CPU cost, switch Declick off.

### Dehum

Removes continuous narrowband tones — mains hum, and the off-frequency drones that turn up on speed-corrected disc transfers — without being told which frequency to look for. It finds the line, tracks it, and cancels it. Latency is zero.

| Control | What it does |
|---|---|
| **Sensitivity** | How far a peak must stand above its surroundings before it counts as a tone. Past about 0.7, clean material starts qualifying. |
| **Rumble** | High-pass corner for broadband turntable rumble — a separate defect that shares the band. 0 turns it off. The 67 Hz default goes after rumble properly and takes the bottom octave of a double bass with it; wind it back towards 40 where the low end is worth keeping. |
| **Bandwidth** | Half width of each notch. 1 Hz costs nothing musically — a partial 5 Hz away loses 0.15 dB. |
| **Search to** | Top of the automatic search range. Hum lives low; searching higher finds sustained musical notes instead. |
| **Harmonics** | Multiples of each line to cancel as well. Mains buzz has them; disc-transfer drones usually do not. |
| **Frequency** | 0 detects the line automatically. Set a frequency to pin the notch when you already know what you are removing. |
| **Dry/Wet** | Blend against the original. At 0 the detector keeps tracking, so switching back is instant. |

Finding a hum takes time — from a few seconds for an obvious line to the better part of a minute for one buried in rumble. TangoDisplay scans the opening of each track in the background as it loads, so the line is usually cancelled from the first bar rather than a minute in.

### Skip on cortinas

On by default. Cortinas are almost always modern digital files, where a declicker only substitutes guesswork and the rumble filter costs real bass, so they play unprocessed while the tandas around them are restored.

### Per-Track Override

Restoration is a global switch, but shellac transfers and modern masters sit side by side in most sets. Right-click any track:

- **Restore this Track** — force restoration on, even if it is off for the set
- **Skip Restoration for this Track** — force it off
- **Use Default Restoration** — clear the override and follow the global rule again

An override outranks both the master switch and the cortina rule, so a single shellac transfer can be repaired in an otherwise unrestored set. Overridden tracks show a small badge in the row — a sparkles icon when restoration is forced on, a no-entry icon when it is forced off. Tracks following the global rule carry no badge.

The toolbar button shows the master switch at a glance: tinted with a dot when restoration is on, plain grey when it is off.

Overrides are saved with the setlist and survive a restart.

---

## 5-Band Equaliser

Click the **Equaliser** button in the toolbar to open the EQ popover.

> **Screenshot placeholder:** EQ popover with five vertical sliders

| Band | Frequency | Type |
|---|---|---|
| Band 1 | 60 Hz | Low shelf |
| Band 2 | 250 Hz | Peaking |
| Band 3 | 1 kHz | Peaking |
| Band 4 | 4 kHz | Peaking |
| Band 5 | 12 kHz | High shelf |

Each band has a vertical slider with a **±12 dB** range. The current gain is shown above each slider.

Click **Flat** to reset all bands to 0 dB in one click.

EQ settings are saved across sessions.

---

## ReplayGain

ReplayGain adjusts playback volume using loudness metadata so every track sounds equally loud without manual volume tweaking. Click the **ReplayGain** button (waveform icon) in the Setlist toolbar to open the quick-access popover, or go to **Settings › Player › ReplayGain** for the same controls alongside the rest of the player settings.

The ReplayGain button is **never disabled** — you can always reach it to change the mode, even when playback is stopped or mode is currently Off.

### Modes

| Mode | How it works |
|---|---|
| **Off** | No gain adjustment is applied. |
| **Track** | Reads the `REPLAYGAIN_TRACK_GAIN` tag embedded in the audio file and applies it directly. |
| **Album** | Reads the `REPLAYGAIN_ALBUM_GAIN` tag instead, preserving the relative volume between tracks in an album. |
| **Auto** *(Recommended)* | Uses embedded ReplayGain tags when present. When a track has no tags, TangoDisplay analyses the audio and calculates the gain needed to reach the **Target Loudness** setting. Analysis runs in the background; a live status line in the player controls shows progress ("Analysing…") and the result once complete (e.g. "Auto +2.3 dB · −18.0 LUFS"). |

### Controls

**Prevent clipping** — when enabled, the calculated gain is capped so the output never exceeds 0 dBFS, regardless of the Preamp setting. On by default.

**Preamp** — a global gain offset applied on top of the ReplayGain value (−12 to +6 dB). Use this to raise or lower the overall volume without touching individual track tags.

**Target Loudness** — the loudness target used when analysing tracks in Auto mode (−23 to −14 LUFS). Only active when mode is set to **Auto**. Default: −18.0 LUFS.

### Live Status Line

While a track is playing with ReplayGain active, a status line appears below the artist name in the player controls showing the active gain adjustment and mode. For example:

- `Auto +2.3 dB · −18.0 LUFS` — gain calculated from analysis
- `Track −1.5 dB` — gain read from embedded tag

The line clears when playback stops or ReplayGain is set to Off.

### Analysis Cache

Loudness analysis results are cached on disk so each file is only analysed once. Subsequent plays of the same file load instantly from the cache.

---

## Audio Unit Plugin Chain

The built-in player can host **up to 4 Audio Unit effect plugins in series** directly in the audio chain — useful for applying EQ curves, dynamics processing, or filtering to improve the clarity of older recordings without modifying the source files. Each slot is independent: you can reorder, bypass, edit, and preset each one separately.

> **Test before you play:** Try your chain at home before using it live. If a plugin fails to load, playback continues unaffected. Third-party Audio Units run at your own risk — an unstable plugin may still interrupt playback.

### Building the Chain

1. Go to **Settings › Player**
2. Open the **Audio Unit Plugins** section
3. Click **Add Plugin** to open the plugin browser and pick an Audio Unit — it loads immediately into the next free slot
4. Repeat to add up to 4 plugins. Audio flows through the slots top to bottom.

If you used a single plugin in an earlier version of TangoDisplay, it is migrated automatically into **slot 1** of the chain on first launch.

### Supported Plugins

The plugin browser lists every effect Audio Unit installed on your system — both `kAudioUnitType_Effect` (plain effects) and `kAudioUnitType_MusicEffect` (effects that also accept MIDI, such as FabFilter Pro-Q 4). This covers Apple's built-in effects (parametric and graphic EQ, dynamics processor, multi-band compressor, peak limiter, shelf and pass filters) and any third-party effects you have installed (e.g. FabFilter Pro-Q 4, Klanghelm MJUC).

Plugins load **out-of-process** by default: each plugin runs in its own process, so if a plugin crashes — whether while processing audio or when you open its editor — the crash is isolated and won't take down TangoDisplay. This is the standard, well-tested hosting path that third-party plugins expect.

A small number of plugins need to be hosted **in-process** for plugin-driven window auto-resize to work (when hosted out-of-process their editor view can't tell the host to grow the window). These are handled via a built-in allowlist — currently Klanghelm MJUC, whose expander panel resizes the editor at runtime. In-process plugins are not crash-isolated.

### Per-Slot Controls

Each slot in the chain has its own controls in **Settings › Player**:

| Control | What it does |
|---|---|
| **▲ / ▼** | Reorder the slot up or down within the chain |
| **Open editor** (expand icon) | Opens that plugin's native editor UI in its own window |
| **Replace…** | Swaps the slot's plugin for a different Audio Unit |
| **Remove** (trash icon) | Removes that plugin from the chain, freeing the slot |

A **Bypass entire chain** toggle at the top of the section lets you mute all effects at once without unloading them. To enable or disable *individual* slots during a set, use the Setlist toolbar popover (below).

### Audio Chain

The plugins occupy up to 4 chained slots, processed in order:

```
┌─────────────┐    ┌──────────────┐    ┌──────────────────────────────────────────────┐    ┌───────────┐
│  Audio File │───▶│  ReplayGain  │───▶│  Slot 1 ─▶ Slot 2 ─▶ Slot 3 ─▶ Slot 4         │───▶│  Output   │
│  (decoder)  │    │  (optional)  │    │  (each optional, bypassable, reorderable)     │    │  Device   │
└─────────────┘    └──────────────┘    └──────────────────────────────────────────────┘    └───────────┘
```

### Presets

Presets let you save and recall a plugin's complete configuration **per slot** — useful for switching between EQ curves for different rooms or recording eras.

**In Settings › Player:**

| Control | What it does |
|---|---|
| Preset picker | Shows the active preset name for that slot (or "None" if unsaved) |
| **Save as Preset…** | Prompts for a name and saves that slot's current parameter state |
| **Delete** | Removes the selected user preset |

Factory presets built into the plugin appear at the top of the picker; your saved presets appear below them.

**In a plugin's floating window:**

A **Preset:** bar at the bottom of each plugin's editor window mirrors the Settings picker for that slot. You can switch or save presets without leaving the window.

**Auto-restore:** Each slot's last-used preset is saved automatically and reapplied the next time the plugin loads.

**Dirty state:** If you adjust any parameter directly in a plugin window (e.g. drag an EQ band), that slot's preset label resets to **None** to show the state no longer matches a saved preset.

### Plugin Configurations

While per-slot **Presets** save a single plugin's parameters, a **Plugin Configuration** snapshots the entire chain state — every slot, every parameter — under one name. You can then assign that configuration to specific setlist tracks so the chain automatically switches when those tracks play.

**Saving a configuration:**

1. Set up your plugin chain exactly as you want it (plugin selection, slot order, parameters)
2. Go to **Settings › Player › Audio Unit Plugins** and click **Save current settings as configuration…**
3. Enter a name — the snapshot is stored immediately

**Managing configurations:**

| Control | What it does |
|---|---|
| Circle icon | Tap to set a configuration as the **default** (applied to all tracks without an explicit assignment) |
| **Remove default** | Clears the default; the chain will not switch automatically for unassigned tracks |
| **Rename** | Rename a saved configuration in place |
| Trash icon | Delete a configuration permanently |

**Assigning a configuration to a setlist track:**

Right-click (or control-click) one or more tracks in the Setlist and choose **Apply Configuration** from the context menu. The track shows a small purple badge with the configuration name. When TangoDisplay plays that track, the chain automatically switches to the assigned configuration — and restores your previous settings when a track without an assignment plays next.

To remove an assignment, right-click the track and choose **Apply Configuration › None**.

### Setlist Toolbar Quick Access

When the chain has at least one plugin, a **puzzle piece button** appears in the Setlist toolbar next to the ReplayGain button. Click it to open a popover for live chain access without going to Settings: enable or bypass the whole chain, toggle individual slots on or off, and open each plugin's editor window.

---

## Decibel Meter

The decibel meter monitors ambient room noise in real time using your Mac's built-in microphone, giving you a live reading of how loud the room is without needing a separate tool.

### Enabling the Decibel Meter

1. Go to **Settings › Player**
2. Under **Built-in Player**, enable the **Enable decibel meter** toggle

macOS will prompt for microphone access the first time you enable it. If you decline or later revoke the permission, an orange warning appears in the settings panel. Grant access in **System Settings › Privacy & Security › Microphone**.

### Toolbar Indicator

When enabled, a live dB reading appears in the Setlist toolbar showing the current room level (e.g. `68 dB`). The reading is colour-coded against your configured range:

| Colour | Meaning |
|---|---|
| Blue | Below the low threshold — room is quieter than expected |
| Green | Within the acceptable range |
| Red | Above the high threshold — room is too loud |

The indicator updates every 250 ms and disappears automatically if microphone permission is denied.

### Setting Your Range

Use the interactive range slider in **Settings › Player › Decibel Meter** to configure your thresholds. The slider shows three colour zones — blue, green, and red — with draggable handles for the low and high boundaries (0–140 dB). The defaults are 60 dB (low) and 80 dB (high).

> **Practical Use Case:** As the noise level can often vary between the DJ booth and the floor, set the noise level with a professional noise meter at floor level. Measure at the desk and set the acceptable range in Setlist.

The meter runs only when enabled — it has no CPU overhead when turned off.

---

## Audio Output

By default the built-in player uses the macOS system default output device. To route audio to a specific device (e.g. a dedicated DJ audio interface):

1. Go to **Player** in the Settings sidebar
2. Under **Built-in Player**, open the **Main output** picker
3. Select your device

The list shows all currently available audio output devices.

> **Pick your interface by name, not "System Default".** On System Default the player follows whatever macOS currently calls the default device — so plugging headphones into the built-in jack moves the player's output to the headphones, and unplugging them moves it to the internal speakers. Selecting the interface by name pins the output to that device regardless of what the system default does.

If the selected device is disconnected, playback stops and an **Audio Device Unavailable** alert appears with a **Retry** button. Reconnect the device and click Retry to resume — the player does not silently fall back to another output.

### Exclusive Mode (Hog Mode)

Enable **Exclusive mode (Hog Mode)** in **Player Settings** to give TangoDisplay exclusive access to the selected audio device. While active, no other app (Music.app, Spotify, system alerts) can use the same interface — useful for DJ setups where you want to guarantee the audio path is clean.

- The toggle is only available when a specific output device is selected (not the system default).
- If another process already owns the device when you enable Hog Mode, an orange warning banner appears in the Setlist view with a **Retry** button. Once the other app releases its hold, tap Retry to acquire exclusive access.
- If another app claims the device *while a track is playing*, a **Playback Interrupted** alert appears. Click **Retry** to re-acquire exclusive access and resume playback, or **OK** to continue without exclusive mode.
- Hog Mode is released automatically when TangoDisplay quits or you switch back to the system default output.

---

## Setlist Remote

The Setlist Remote lets you control the built-in player from your phone (or any device with a browser) over the same Wi-Fi network. It serves a small built-in web page with sliders for the main controls — useful when you want to nudge levels from the dance floor without going back to the laptop.

Enable it in **Settings › Player › Setlist Remote**.

> Setlist Remote is for the built-in player only — its sliders move the built-in player's volume and ReplayGain settings.

### What the phone page controls

| Control | What it does |
|---|---|
| **Volume** | Master output level of the built-in player |
| **Cortina volume** | Per-cortina attenuation (the same slider as **Player › Cortinas › Cortina volume**) |
| **Replay gain** | The active ReplayGain pre-amp / fallback gain used by the player |

### Connecting

| Element | Description |
|---|---|
| **URL** | The IP-based URL your phone connects to (e.g. `http://192.168.1.42:4747`). A second URL using the Mac's `.local` hostname is shown when available |
| **QR code** | Scan from your phone's camera to open the URL directly |
| **PIN** | A 4-digit code the page asks for before unlocking the controls. **The PIN regenerates each time TangoDisplay launches** — anyone on the Wi-Fi who knows it can connect, so it is rotated automatically |
| **Connected** | How many clients are currently connected |

### Buttons

| Button | What it does |
|---|---|
| **Regenerate PIN** | Issues a new 4-digit PIN immediately (existing connections are dropped) |
| **Refresh URL** | Re-reads the Mac's current Wi-Fi address — use after switching networks |
| **Open in Browser** | Opens the remote page in your Mac's browser, useful for testing |

### Requirements & limitations

- The phone and the Mac must be on the **same Wi-Fi network**. The remote does not work over cellular or across different networks.
- If the Mac is not connected to Wi-Fi, the panel shows a warning and the URL is unavailable.
- The PIN is not persisted — it changes on every launch by design.
- The remote is for the **built-in player only**. With Music.app, Swinsian, or Embrace selected, the toggle still works but the sliders have no effect on those external players.

---

## Integration with the Display

When the built-in player is active, the dancer display responds exactly as it does with Music.app:

- **Cortina detection** — your [Cortina Rules](Cortina-Rules) apply to every setlist track. A track whose genre matches a cortina rule triggers cortina mode on the display automatically.
- **Tanda counting** — TangoDisplay counts consecutive non-cortina tracks to determine tanda position (e.g. "Track 2 of 4").
- **Coming-Up preview** — during a cortina, the next tanda's first dance track is shown as the "Coming Up" track on the display. Use [Edit Upcoming Info](#edit-upcoming-info) to type your own artist, singer and year for a mixed tanda.
- **Album artwork** — extracted from the audio file and shown on the dancer display (if artwork display is enabled in Appearance settings).

No additional configuration is needed — the display sync is fully automatic.

---

## Player Settings Reference

Go to **Player** in the Settings sidebar.

> **Screenshot placeholder:** Player Settings view showing all sections

### Player Source

Choose which player TangoDisplay listens to:

| Source | How it works |
|---|---|
| **Music.app** | Polls via AppleScript every 2 seconds. Full tanda counting and playlist look-ahead. |
| **Swinsian** | Real-time push notifications. Tanda position shown; total track count unavailable. |
| **Embrace** | Real-time notifications + AppleScript polling. Full tanda counting. |
| **Built-in Player** | TangoDisplay plays audio directly. Build your setlist in the Setlist tab. |

### Built-in Player Settings

These options appear only when **Built-in Player** is selected.

**Main output** — the audio device to use for playback. Defaults to the macOS system output.

**Cortina fade** — duration of the volume fade used by Fade & Stop and Fade & Continue (1–15 seconds, in 0.5-second steps). Default: 5 seconds.

**Duplicate track protection** — when enabled, dropping a track that already exists in the setlist shows a confirmation alert before adding it. Includes a **Remember for this session** checkbox that silences the prompt for the rest of the session (until the setlist is cleared). Off by default.

**Auto-gap** — when enabled, TangoDisplay analyses silence at track boundaries and pads each transition with a silent preroll so the gap always meets the minimum. Only silence is added — existing gaps are never shortened.

**Minimum gap** — the target gap duration in seconds (0.5–5 s, in 0.5-second steps). Default: 4 seconds. Visible only when Auto-gap is enabled.

**Skip gap before first track** — when on (default), the first track in the setlist starts immediately with no silence preroll. The gap applies only between consecutive tracks.

**Skip gap after manual stop** — when enabled, the next track started after a manually stopped track plays immediately with no silence preroll. Applies to the transport stop button and Fade & Stop. Off by default. Visible only when Auto-gap is enabled.

**Auto-fade all cortinas** — when enabled, TangoDisplay automatically fades out cortinas and advances to the next track at the configured play time. Requires cortina detection to be set up via Cortina Rules.

**Cortina play time** — how many seconds of a cortina should play before the auto-fade begins (5–120 s, in 1-second steps). Default: 30 seconds. Visible only when Auto-fade is enabled. For cortinas shorter than play time + fade duration, the fade starts earlier so it always completes cleanly.

**Enable decibel meter** — when enabled, TangoDisplay monitors ambient room noise using the Mac's built-in microphone and shows a live colour-coded dB reading in the Setlist toolbar. Requires microphone permission.

**Decibel meter range** — an interactive three-zone slider to configure the low and high thresholds (0–140 dB). Readings below the low threshold appear blue, within range appear green, and above the high threshold appear red. Defaults: 60 dB (low), 80 dB (high). Visible only when the decibel meter is enabled.

**Mark as played** — controls when a track receives its played stamp:

| Option | Behaviour |
|---|---|
| **After song ends** | The track is marked only when it plays all the way to completion |
| **After…** | The track is marked after a set number of seconds of playback (1–30 seconds). A marker line on the seek bar shows the threshold. Once marked, pressing play again skips to the next queued track. |

### ReplayGain Settings

**ReplayGain mode** — Off, Track, Album, or Auto (recommended). Auto uses embedded tags when present and analyses the file against the target loudness when absent.

**Prevent clipping** — caps the output at 0 dBFS. Active for Track, Album, and Auto modes.

**Preamp** — global gain offset on top of ReplayGain (−12 to +6 dB). Active for Track, Album, and Auto modes.

**Target Loudness** — the LUFS target used when Auto mode analyses a file (−23 to −14 LUFS). Active in Auto mode only.

### Track Info

Toggles for which fields appear in setlist rows (visible only with Built-in Player selected):

| Field | Default | Notes |
|---|---|---|
| Title | Always on | Cannot be hidden |
| Artist | Always on | Cannot be hidden |
| Genre | Always on | Cannot be hidden |
| Year | On | |
| Time | On | Shows duration and current position |
| Comments | Off | |
| Album Artist | Off | |
| Grouping | Off | |

### Genre Colours

Assign custom colours to genre tags for upcoming (unplayed) tracks — giving a clear visual map of the tanda structure ahead.

**Enable/disable:** Toggle **Genre tag colours** in **Settings › Player › Genre Colours**.

**Adding a rule:**

1. Type a keyword in the text field (e.g. `tango`)
2. Pick a colour with the colour picker
3. Click **Add**

Keywords are case-insensitive and match anywhere in the genre name — `tango` matches `Tango`, `Argentine Tango`, `Tango Nuevo`, etc.

**Colour priority:**

| Track state | Genre tag colour |
|---|---|
| Playing | Green (always) |
| Paused (armed) | Orange (always) |
| Next to play | Accent blue (always) |
| Already played | Grey (always) |
| Upcoming / queued — Cortina | Bold/bright (always, even when colours are ON) |
| Upcoming / queued — keyword match | Your custom colour |
| Upcoming / queued — no match | Grey |

**When genre colours are OFF:** upcoming (unplayed) tracks are shown in semibold with full-brightness text so they stand out clearly from already-played tracks, regardless of any colour rules.

**Cortinas always appear bold/bright** — even when genre colours are enabled and a colour rule would otherwise match the cortina's genre tag. This ensures tanda breaks are always easy to spot.

Custom colours apply only to non-cortina tracks that have not yet been played and are not currently playing — the tanda structure is visible at a glance without interfering with standard playback indicators.

To remove a custom colour, click the **trash** icon next to the rule. The genre tag reverts to standard grey for upcoming tracks.

**Include song title:** When enabled (toggle in **Settings › Player › Genre Colours**), the genre tag colour also applies to the song title text in the setlist row, not just the genre badge.

### Track Info Transformations

The **Advanced** tab in Settings lets you apply optional regex-based rules to reformat how Artist, Title, Year, Album Artist, and Comments are displayed on the dancer screen — without modifying the original music tags. See [Advanced Settings](Advanced-Settings) for full details and examples.

---

## Reports Tab

The Reports tab (sidebar › **Reports**) stores setlist snapshots you've saved during or after a milonga.

### Saving a report

In the Setlist tab, open the **Share** menu (↑ icon in the toolbar) and choose **Save Setlist Report…**. Enter a name for the report — it defaults to a timestamp — then click **Save**. The snapshot captures every track's title, artist, genre, year, duration, play state, and last-tanda flag at the moment of saving.

### Exporting an HTML report

Select one or more reports in the list, then click **Generate HTML Report**. TangoDisplay creates a self-contained HTML file you can open in any browser or share with others. The report includes:

- **Summary cards** — total tracks, played count, total duration, year range, unique artists and genres
- **Per-setlist summary table** (when multiple reports are combined)
- **Top 10 most-played tracks** across all selected setlists
- **Genre breakdown charts** — artists by genre, year range by genre, and time played by genre (rendered with Chart.js)
- **Full track listing** — sortable columns and accent-insensitive search

### Managing reports

- **Select multiple** — ⌘-click or use the checkboxes to select several reports before generating a combined export.
- **Delete** — select one or more reports and click **Delete**. A confirmation prompt appears before anything is removed.
