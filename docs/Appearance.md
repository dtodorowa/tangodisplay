# Appearance

The **Appearance** tab controls everything about how the dancer display looks. Settings are organised into six tabs accessible via the tab bar at the top of the panel:

| Tab | What it controls |
|---|---|
| **Visibility** | Which fields are shown on the display, and the order they appear in |
| **Text** | Font, size, and style for each text element |
| **Colours** | Colour of each element on the dancer display |
| **Artwork & Motion** | Transition style and duration, album artwork, background image, and artist backgrounds |
| **Cortina** | What is shown on-screen during a cortina |
| **Last Tanda** | Last Tanda announcement label settings |
| **Performance** | Background image and text lines shown when a performance track is playing |

---

## Visibility

### Field Visibility

Control which fields are shown — independently for dance tracks and for the cortina "Coming Up" preview. Each row has two toggles: **Dance** (shown while a tanda is playing) and **Next Up** (shown in the next-track preview during a cortina).

| Field | Dance default | Next Up default |
|---|---|---|
| **Genre** | On | On |
| **Artist** | On | On |
| **Year** | Off | Off |
| **Title** | On | Off |
| **Singer** | Off | Off |
| **Artwork** | Off | Off |

**Show next track during cortina** — hides or shows the entire "Coming Up" next-track preview section. When off, the Next Up column toggles have no effect.

The Coming Up values come from the next tanda's first track. With the built-in player you can type your own artist, singer and year for one cortina — see [Edit Upcoming Info](Built-In-Player#edit-upcoming-info).

### Text Order

Control the vertical order in which text items appear on the dancer display. There are three independent orderings — one for dance tracks, and two for cortinas.

| Section | What it controls |
|---|---|
| **Dance Tracks** | Order of items on the main display while a tanda is playing |
| **Cortinas — Cortina Track** | Order of Cortina Label, Cortina Artist, and Cortina Title on the cortina screen |
| **Cortinas — Coming Up** | Order of Next Up Label and next-tanda preview items during cortinas |

Use the **↑** and **↓** chevron buttons on the right of each row to move items up or down. Changes take effect on the dancer display immediately.

**Dance Tracks** items: Genre, Artist, Year, Title, Singer, Last Tanda Label, Track Counter (only visible when position is "Centred (in text order)" in Display Settings), TDJ Name (only visible when DJ Name position is "Centred (in text order)" in Display Settings)

**Cortinas — Cortina Track** items: Cortina Label, Cortina Artist, Cortina Title (default order: label first, then artist, then title). Only visible when **Show cortina track during cortina** is enabled in the Cortina tab.

**Cortinas — Coming Up** items: Next Up Label, Genre, Artist, Year, Singer, Title, Last Tanda Label. The Next Up Label ("COMING UP" heading) is an orderable item — move it anywhere in the preview block.

### Custom Lines

Add your own free-text lines to the display, on top of the built-in fields. Each custom line is a template that can mix plain text with **placeholders** drawn from the playing (or upcoming) track's metadata.

To add a line, click **Add Custom Line** in the Custom Lines section, then type a template, for example:

```
{Artist} {Year} ({Genre}) {Title} ({Singer})
```

**Available placeholders** (case-insensitive — `{Artist}` and `{artist}` both work):

| Placeholder | Resolves to |
|---|---|
| `{Artist}` | Track artist |
| `{Title}` | Track title |
| `{Genre}` | Track genre |
| `{Year}` | Track year |
| `{Singer}` | The Singer field (from the source set in **Singer Source**) |
| `{AlbumArtist}` | Album Artist tag |
| `{Comment}` | Comments tag |
| `{Grouping}` | Grouping tag |

Any text outside the braces is shown verbatim, and an empty placeholder (e.g. a track with no year) simply collapses to nothing. Field values respect the same text transforms as the built-in fields.

Each line has its own **font, size, bold/italic, and colour**, plus independent **Dance** and **Next Up** visibility toggles in **Field Visibility** above. New lines are added to both the **Dance Tracks** and **Cortinas — Coming Up** orderings, where they can be reordered among the built-in items like any other field.

---

## Text

Configure the typeface, size, and style for each text element:

| Column | What you set |
|---|---|
| Font name | Choose from installed system fonts |
| Size | Point size of the text (use the stepper to adjust) |
| **B** | Bold |
| *I* | Italic |

The section is divided into three groups:

**Label rows** (at the top): **Cortina Lbl** (the "CORTINA" heading), **Next Up Lbl** (the "COMING UP" heading), and **Idle Msg** (the idle-state message). These have independent font and color control.

**Dance track rows**: **Artist**, **Title**, **Genre**, **Year**, and **Singer**. Whether each field is shown is controlled in the **Visibility** tab.

**Cortina track rows** (at the bottom): **Cortina Art.** and **Cortina Ttl.** — the font for the cortina track's own artist and title when cortina track display is enabled.

### Singer Source

A **Source** picker lets you choose where the singer name comes from:

| Source | Description |
|---|---|
| **Comments** | Reads the track's Comment metadata field. Useful when you've tagged vocalist names into comments in your library. This is the default and matches the behaviour of earlier versions. |
| **Album Artist** | Reads the Album Artist metadata field. Useful when Album Artist holds the vocalist name (common in some tango library workflows). |

A **Singer** font row appears below the source picker so you can set the typeface, size, and style independently of the other text elements.

### Override Text

An **Override Text** section at the bottom of the Text tab lets you set the font for the manually-entered override message (⌘⇧O). Its colour is set in the Colours tab under **Override text**.

---

## Colours

Set the colour of each element on the dancer display:

| Element | What it colours |
|---|---|
| **Background** | The solid background fill (used when no background image is set, or behind a semi-transparent image) |
| **Artist** | The large artist/orchestra name text |
| **Title** | The track title text |
| **Genre/label** | The smaller genre or record label line |
| **Year** | The recording year (e.g. 1952) |
| **Track counter** | The "Track X of X" text in the corner |
| **Singer** | The vocalist/singer line |
| **Cortina label** | The "CORTINA" heading text on the cortina screen |
| **Next up label** | The "COMING UP" heading text in the cortina preview |
| **Cortina artist** | The cortina track's own artist (when cortina track display is enabled) |
| **Cortina title** | The cortina track's own title (when cortina track display is enabled) |
| **Idle message** | The text shown when nothing is playing |
| **Last Tanda label** | The Last Tanda announcement text when Last Tanda mode is active |
| **Override text** | The manually-entered override message shown via ⌘⇧O |

Click any colour swatch to open the macOS colour picker.

---

## Artwork & Motion

### Transition

| Setting | Description |
|---|---|
| **Style** | How the display transitions between tracks. Options: *Crossfade*, *Hard Cut*, *Fade Through Black*, *Push* (slides in from the right), and *Zoom* (scales in/out). |
| **Duration** | Length of the transition in seconds (drag the slider). |

### Album Artwork

Configure how album artwork appears on the dancer screen. Artwork visibility is controlled per context in the **Visibility** tab — these sliders only take effect when artwork is enabled for Dance or Next Up (or both).

| Control | Description |
|---|---|
| **Opacity** | 0 % = invisible, 100 % = fully opaque |
| **Edge Fade** | 0 % = hard edges, 100 % = maximum radial fade. Softly blends the edges of the artwork into the background |
| **Scale** | 1× = natural size; increase to fill more of the screen |
| **Horizontal offset** | Move the artwork left (negative) or right (positive) |
| **Vertical offset** | Move the artwork up (negative) or down (positive) |

Artwork is fetched automatically from the playing track for all three player sources — Music.app, Swinsian, and Embrace. It fades in and out in sync with track transitions using the same transition style and duration configured above. When no artwork is available the display falls back gracefully (nothing is shown in that layer).

### Background Image

| Control | Description |
|---|---|
| **Pick Image… / Change Image…** | Opens a file picker to select any image file (label changes to *Change Image…* once an image is loaded) |
| **Clear** | Removes the background image |
| **Opacity** | 0 % = fully transparent (solid background colour shows), 100 % = fully opaque |
| **Scale** | Zoom the image in or out (1× = original size, higher = zoomed in) |
| **Horizontal** | Pan the image left or right |
| **Vertical** | Pan the image up or down |

Use Scale + Horizontal + Vertical to frame exactly the part of the image you want behind the text.

### Artist Backgrounds

Map specific artist names to background images. When enabled and the currently playing track's artist contains a configured name, the matching image is shown instead of the profile background image. If no artist matches, the display falls back to the profile background image, then to the background colour. The background clears automatically when the display is paused or no track is playing.

| Control | Description |
|---|---|
| **Enable artist backgrounds** | Master switch for this feature |
| **Add Artist…** | Adds a new entry to the list |
| **Artist name field** | Text to match against the playing track's artist. Matching is partial, case-insensitive, and accent-insensitive — "troilo" matches "Anibal Troilo y su Orquesta" |
| **Pick Image… / Change Image…** | Choose the background image for this artist entry |
| **Clear** | Removes the image for this entry |
| **✕** | Removes the entire entry |
| **Opacity** | Opacity applied to all artist background images |
| **Scale** | Zoom applied to all artist background images |
| **Horizontal / Vertical** | Pan all artist background images |

> Each entry must have both a name and an image before you can save. Entries missing either are flagged with a red indicator and the Save button is disabled until resolved.

Priority order: **matching artist background → matching genre background → profile background image → background colour**

### Genre Backgrounds

Map specific genres to background images. The list of entries is driven by your **Cortina Rules** — every genre keyword you've added there appears here as a slot, plus one extra **Cortina** slot for when a cortina is playing. When enabled and the playing track's genre matches an entry that has an image set, the matching image is shown.

| Control | Description |
|---|---|
| **Enable genre backgrounds** | Master switch for this feature |
| **Genre rows** | One row per Cortina Rules entry, plus a dedicated row for cortinas. Use **Pick Image… / Change Image…** to set an image, **Clear** to remove it |
| **Opacity** | Opacity applied to all genre background images |
| **Scale** | Zoom applied to all genre background images |
| **Horizontal / Vertical** | Pan all genre background images |

> To add or remove genre slots, edit your entries in **Cortina Rules**. Slots without an image are simply skipped at runtime.

Priority order: **matching artist background → matching genre background → profile background image → background colour**

---

## Cortina

Controls what is displayed on screen while a cortina is playing.

| Setting | Description |
|---|---|
| **Show cortina track during cortina** | Displays the playing cortina's own track information on the cortina screen |
| **Show next track during cortina** | Shows the "Coming Up" next-tanda preview during the cortina. When off, the cortina screen shows only the cortina label (and cortina track info if enabled) with no preview content. |
| **Show Cortina Artist** | The artist/orchestra of the playing cortina track. Only active when *Show cortina track during cortina* is on. |
| **Show Cortina Title** | The title of the playing cortina track. Only active when *Show cortina track during cortina* is on. |

The text labels ("CORTINA", "COMING UP") and idle message are configured in **Display Settings › Display Labels** and are shared across all profiles.

---

## Last Tanda

Configure the Last Tanda announcement label — displayed on the dancer screen when Last Tanda mode is active.

| Setting | Description |
|---|---|
| **Label text** | The text shown on the dancer display (e.g. LAST TANDA). Stored globally, not per-profile. Leaving this blank disables the Last Tanda toggle on the Live screen. |
| **Colour** | Colour of the label text |
| **Font** | Typeface, size, bold, and italic for the label |
| **Show in display** | Per-profile master switch — when off, the label never appears even if Last Tanda mode is active. Also disables the Last Tanda toggle on the Live screen for this profile. |

> **Label text** is shared across all profiles. **Colour**, **Font**, and **Show in display** are saved per-profile.

The label's vertical position within the dance track and cortina coming-up layouts is controlled in **Text Order** (Visibility tab).

---

## Performance

Configure the dancer display shown when a **performance track** is playing. Performance tracks are marked in the Setlist via right-click › **Mark as Performance** — see [Built-In Player › Performance Tracks](Built-In-Player#performance-tracks) for details on marking tracks and auto-stop behaviour.

### Background Image

| Control | Description |
|---|---|
| **Pick Image… / Change Image…** | Opens a file picker to select a background image shown only during performance tracks |
| **Clear** | Removes the performance background image |
| **Show during cortina** | When enabled, the performance background image also appears during the cortina that immediately precedes the performance track. Visible only when an image is set. |

### Text Lines

Add one or more text lines that appear on the performance display, each independently styled:

| Control | Description |
|---|---|
| **+** | Adds a new text line |
| **Text field** | The text to display. Supports placeholders: `{title}`, `{artist}`, `{genre}`, `{year}` — replaced with the playing track's metadata at runtime |
| **Font picker** | Choose from installed system fonts |
| **Size** | Point size of the text |
| **Colour swatch** | Opens the macOS colour picker for this line's text colour |
| **Show during cortina** | When enabled, this line also appears on the cortina screen during the cortina that precedes the performance |
| **✕** | Removes this line |

Lines are rendered top to bottom in the order they appear in the list.

---

## Saving your settings

- **Save** — updates the currently active profile with the new settings
- **Save as New Profile…** — creates a new named profile (see [Profiles](Profiles))

Changes take effect on the dancer display immediately.
