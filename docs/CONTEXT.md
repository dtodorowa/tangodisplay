# TangoDisplay

TangoDisplay is a macOS app for tango DJs. It shows dancers what is playing, can play the milonga setlist itself, and in this fork lets the DJ prelisten Music playlists without affecting the room.

## Language

### Milonga

**Milonga**:
A social tango dance event, and the room of dancers the DJ plays for.
_Avoid_: party, gig

**Tanda**:
A group of usually three or four dance tracks in one style, often by one orchestra, played between two cortinas.
_Avoid_: set, block

**Cortina**:
A short non-dance track between tandas that tells dancers to clear the floor.
_Avoid_: break, interlude

**Dancer display**:
The screen facing the dancers that shows the current tanda, what's coming up during a cortina, and messages from the DJ.
_Avoid_: presentation window, TV

**Main output**:
The audio device the room hears.
_Avoid_: speakers, program output

### Setlist

**Setlist**:
The ordered tracks the built-in player plays to the main output during a milonga. Played tracks stay in place and can't be moved.
_Avoid_: playlist, queue

**Built-in player**:
TangoDisplay's own player for the setlist, used instead of an external player such as Music or Embrace.
_Avoid_: local player, setlist player

### Music library

**Music library**:
The DJ's library in Apple's Music app. TangoDisplay reads it and never changes it.
_Avoid_: iTunes library, Apple Music

**Playlist**:
A named, ordered list of tracks the DJ keeps in Music, either regular or smart.
_Avoid_: setlist, tanda list

**Playlist folder**:
A named group of playlists in Music.
_Avoid_: category

**Track**:
One recording in the Music library. Its audio file is on this Mac or only in iCloud.
_Avoid_: song, file

**Row**:
One position in a playlist. A track listed twice in a playlist is two rows.
_Avoid_: duplicate, entry, occurrence

**Start and stop times**:
The part of a track the DJ has marked in Music to play instead of the whole recording.
_Avoid_: trim, cue points

### Prelisten

**Prelisten**:
Playing rows for the DJ or a class without touching the setlist or the dancer display.
_Avoid_: preview, cue, pre-listening

**Prelisten queue**:
The rows that were showing when prelisten playback started, played in that order.
_Avoid_: up next

**Prelisten output**:
The audio device prelisten plays to, chosen separately from the main output. Usually headphones, or class speakers when teaching.
_Avoid_: cue output, headphones

**Column browser**:
Lists of values above a playlist's rows, as in Music. Genres, Artists, Albums and Comments unless the DJ right-clicks to pick other lists or move them. Picking values in one list narrows the lists to its right and the rows. Some DJs keep the singer in Comments, so picking one there shows only that singer's rows.
_Avoid_: filters, facets, tag browser

**Year range**:
The recording years prelisten rows are narrowed to, such as 1935 to 1945. Rows without a year drop out while a range is set.
_Avoid_: date filter

**Auto-advance**:
Prelisten moving on to the next row when one ends. With it off, prelisten stops after each row.
_Avoid_: autoplay, continuous play

**Prelisten pane**:
Prelisten shown inside the main window next to the current tab, docked on the left, right, or bottom.
_Avoid_: module, panel, sidebar

**Prelisten window**:
Prelisten in a window of its own.
_Avoid_: popout
