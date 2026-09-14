# The fork ships as a separate "TangoDisplay Prelisten" app

Prelisten lives in a fork ([dtodorowa/tangodisplay](https://github.com/dtodorowa/tangodisplay), branch `prelisten`) rather than upstream, because upstream has closed feature requests from other users as not planned ([issue #4](https://github.com/richardsladetdj-creator/TangoDisplay/issues/4)). To keep pulling upstream releases cheap, new code goes in new files and upstream files only get small additions. `Scripts/BuildPrelisten.sh` builds the fork as "TangoDisplay Prelisten" with its own bundle ID, `com.local.tangodisplay.prelisten`, into `build/` instead of `/Applications`, so it can run on a Mac that also has upstream TangoDisplay installed.

## Consequences

- Upstream files with prelisten changes: `AppState`, `AppSettings`, `TangoDisplayApp`, `ControlView`, `SetlistView` (drop guard and paste) and the test runner. Check these first when merging an upstream release.
- Settings and macOS permissions are separate from the installed TangoDisplay. Both apps keep the setlist in the same Application Support folder and register the same global hotkeys, so don't run them at the same time.
- Sparkle's feed points at a fork appcast that doesn't exist, and automatic update checks are off, so the updater never offers an upstream build that would replace the fork. The version badge still checks upstream's GitHub releases.
- Builds are ad-hoc signed, so macOS may ask for Music library access again after a rebuild. `tccutil reset MediaLibrary com.local.tangodisplay.prelisten` resets it.
- `Install.sh` builds upstream's app identity and replaces `/Applications/TangoDisplay.app`. Use `Scripts/BuildPrelisten.sh` for the fork.
