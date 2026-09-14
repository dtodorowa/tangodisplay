# Prelisten reads the Music library and never writes to it

Prelisten reads playlists, playlist folders, tracks and start and stop times through Apple's iTunesLibrary framework, which TangoDisplay already used for start and stop times and which still works on Tahoe. The framework is read-only, and Music's scripting interface, the only way to edit Music from another app, is broken on Tahoe. So prelisten doesn't create, reorder or edit playlists. The DJ keeps building tandas in Music, reloads in prelisten to see the changes, and moves tracks into the setlist with Add to Setlist, drag, or ⌘C/⌘V.

## Considered Options

- **Write changes back to Music with AppleScript.** Broken on Tahoe ([Apple Developer Forums thread 801357](https://developer.apple.com/forums/thread/801357)).
- **Keep TangoDisplay's own copies of playlists and edit those.** Prelisten would become a second library that has to stay in sync with Music, and the DJ's playlists have lived in Music for years.

## Consequences

- Building a tanda still happens in Music, where playing a repeated track still jumps. Prelisten fixes listening; editing is unchanged.
- Changes made in Music appear in prelisten after a reload.
- Revisit this if Apple fixes Music scripting, or if the DJ needs to build tandas without leaving TangoDisplay.
