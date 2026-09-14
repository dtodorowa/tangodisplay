# Prelisten plays Music playlists itself, row by row

Since macOS Tahoe, Music.app's playback jumps around when a playlist lists the same track more than once. A tango DJ who also teaches hit this while building tandas, prelistening, teaching classes and giving demos; only playing a list straight from top to bottom worked. We decided TangoDisplay plays those playlists itself: it reads them from the Music library and plays rows in playlist order on its own audio engine, so a track listed twice is two separate rows.

## Considered Options

- **Stay in Music and give each repeat its own library entry.** Copy the audio file and swap the copy into the playlist. The DJ keeps Music's interface, but ratings and play counts split across copies, and doing this for years of playlists needs Music scripting, which is broken on Tahoe ([Apple Developer Forums thread 801357](https://developer.apple.com/forums/thread/801357)).
- **A companion app that opens tracks in Music.** Playback still happens in Music, so the jumping stays.
- **Switch players.** Swinsian is closed source and the DJ doesn't like it. TangoDJ costs $199. Embrace isn't supported after macOS Sonoma.
- **Downgrade to Sequoia.** Fixes the bug, but means erasing the Mac and staying on an older macOS.
- **Reuse the setlist's built-in player.** It already handles repeated tracks, but it is built for a milonga: played rows lock, stopping takes two clicks, and whatever it plays drives the dancer display and the main output.

## Consequences

- Prelisten has its own player and its own prelisten output, so the DJ can listen on headphones while the setlist plays to the room.
- When the audio output changes, for example when headphones are unplugged, prelisten pauses. macOS may have moved the default output to the room speakers.
- Prelisten warns when its output is the setlist's main output while the setlist is playing.
- The prelisten queue is fixed when playback starts. Browsing other playlists doesn't change what plays next.
- Start and stop times set in Music apply in prelisten.
- Tracks that exist only in iCloud show dimmed and can't play.
- Rows dragged out of prelisten carry a TangoDisplay-only marker, and the setlist's window-wide drop handler ignores drags with it. Without the marker, letting go anywhere over the prelisten pane would add the tracks to the setlist. Dropping onto an empty setlist therefore does nothing; Add to Setlist and ⌘C/⌘V cover that case.
- ⌘C puts track info on the clipboard under a TangoDisplay-only type instead of Music's own, so pasting into Music never receives half a Music plist. The setlist's paste reads that type so start and stop times come along.
- Unchecked as of 2026-09-14: that Apple's iTunesLibrary framework returns a repeated track once for each row. This approach depends on it.
