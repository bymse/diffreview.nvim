# UI

## Quickfix list
 
- Use a native quickfix list as a flat changed-file list and review queue.
- Each quickfix entry represents one changed file and visibly indicates whether it is viewed or unviewed.
- Order unviewed files before viewed files while preserving comparison order within each group.
- Opening an entry hides the quickfix drawer and selects that file for review in the session's current view mode.
- The reviewer can toggle viewed state for the current entry or a selected quickfix range.
- Viewed state is explicit; merely opening or navigating through a file does not mark it viewed.
- Marking the active file viewed opens the next unviewed file in queue order when one exists.
- The file and comment lists use the same bottom drawer. Opening one closes the other, and invoking the currently open list again closes the drawer.

## Hierarchy of files 

Additional mode:
- Files are grouped by directories
- Files and directories are shown as oil buffer 
- File state (viewed/unviewed) is shown as icon 
- Dir is marked as viewed if all files in the dir are viewed 
- Files and dirs can be marked as viewed from the oil buffer 

## Changes view
Review views run in a dedicated tabpage owned by the active session. The tabpage uses plugin-owned windows while real file buffers remain user-owned.

"diff" mode opens a selected review file using the configured window layout. It uses real file buffers when available and scratch buffers for content loaded from Git.

### Diff mode cases

- Modified text file: Display the old and current versions in the configured two-window layout and enable `diffthis` in both windows. If the mode also changed, show the mode transition in the current window's winbar.
- Added or untracked text file: Display only the current buffer, show `Added file` in its winbar, and highlight every line with `DiffAdd` extmarks.
- Deleted text file: Display the old content in one read-only scratch buffer, show `Deleted file` in its winbar, and highlight every line with `DiffDelete` extmarks.
- Renamed text file: If content is unchanged, display only the current buffer with `Moved from <old_path>` in its winbar. If content changed, display the configured two-window diff and show the move in the current window's winbar.
- Copied text file: If content is unchanged, display only the current buffer with `Copied from <old_path>` in its winbar. If content changed, display the configured two-window diff and show the copy in the current window's winbar.
- Mode-only change: Display one read-only information buffer containing the mode transition and explanatory text describing the old and new modes.
- Type change: Display one read-only information buffer explaining the old and new file types and modes without a text diff.
- Binary file: Display one read-only information buffer containing the paths, status, and available object or size information.
- Unmerged file: Display the current conflict buffer with its conflict markers and show `Unmerged file` in its winbar.
- Content load error: Display one read-only information buffer containing the path, attempted operation, and error message.

"inline" mode displays a selected review file in one window with normal buffer navigation. It uses a real file buffer when a usable path exists and a scratch buffer for content loaded from Git. The UI calculates text hunks from the old and current versions; no parsed hunk input is required.

### Inline mode cases

- Modified text file: Display the current buffer and mark added and changed lines with sign-column markers and `DiffAdd` or `DiffChange` line highlights. Mark each deleted hunk with a `DiffDelete` sign at the nearest surviving line. An explicit preview action temporarily shows that hunk's deleted old lines as virtual lines.
- Added or untracked text file: Display the current buffer, show `Added file` in its winbar, and place an added sign on every line without full-line highlights.
- Deleted text file: Display the old content in one read-only buffer, show `Deleted file` in its winbar, and place a deletion sign on every line without full-line highlights.
- Renamed text file: Display the current buffer and show `Moved from <old_path>` in its winbar. If content changed, use the same signs, line highlights, deleted-hunk markers, and temporary deletion previews as a modified text file.
- Copied text file: Display the current buffer and show `Copied from <old_path>` in its winbar. If content changed, use the same signs, line highlights, deleted-hunk markers, and temporary deletion previews as a modified text file.
- Mode-only change: Display the current buffer, explain the mode transition in its winbar, and add no line decorations.
- Text and mode change: Display the normal modified-file decorations and temporary deletion previews together with the explained mode transition in the winbar.
- Type change: Display one read-only information buffer explaining the old and current types and modes without inline content decorations.
- Binary file: Display one read-only information buffer containing the operation, paths, and available object or size information.
- Unmerged file: Display the current working-tree buffer with its conflict markers and show `Unmerged file` in its winbar without additional conflict-region decorations.
- Content load error: Display one read-only information buffer containing the path, attempted operation, and error message.

## Project navigation

- Normal project navigation, including jumps, file commands, quickfix, and external pickers, remains available during a review.
- Entering a changed file automatically displays it in the selected review mode. Unchanged files open normally without review decorations.
- Diff mode keeps focus on the current file and updates or closes its old-version companion as navigation moves between files.
- Deleted files have no working-tree path and can only be opened from the review file list.

## Comments 
- Comments are shown as virtual text 
- Stale comments are marked in the virtual text 
- User can comment any part of the code in the review mode: changed and unchanged lines
- Comment editor is editable buffer for virtual temporary file. If comment text is deleted then comment is deleted 
- List of comments can be shown through special command
