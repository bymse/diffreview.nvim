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
"diff" mode opens a selected review file using the configured window layout. It uses real file buffers when a usable path exists and scratch buffers for content loaded from Git. A current side supplied by another Git revision uses `current_content` when no usable working-tree path exists.

### Diff mode cases

- Modified text file: Required arguments are `old_path`, `new_path`, `old_content`, and either `current_path` or `current_content`. Display the old and current versions in the configured two-window layout and enable `diffthis` in both windows. If the mode also changed, additionally require `old_mode` and `new_mode` and show the mode transition in the current window's winbar.
- Added or untracked text file: Required arguments are `new_path` and `current_path` when a usable file exists, otherwise `current_content`. Display only the current buffer, show `Added file` in its winbar, and highlight every line with `DiffAdd` extmarks.
- Deleted text file: Required arguments are `old_path` and `old_content`. Display the old content in one read-only scratch buffer, show `Deleted file` in its winbar, and highlight every line with `DiffDelete` extmarks.
- Renamed text file: Required arguments are `old_path`, `new_path`, `old_content`, and either `current_path` or `current_content`. If content is unchanged, display only the current buffer with `Moved from <old_path>` in its winbar. If content changed, display the configured two-window diff and show the move in the current window's winbar.
- Copied text file: Required arguments are source `old_path`, destination `new_path`, `old_content`, and either `current_path` or `current_content`. If content is unchanged, display only the current buffer with `Copied from <old_path>` in its winbar. If content changed, display the configured two-window diff and show the copy in the current window's winbar.
- Mode-only change: Required arguments are the file path, `old_mode`, and `new_mode`. Display one read-only information buffer containing the mode transition and explanatory text describing the old and new modes.
- Type change: Required arguments are the file path, `old_mode`, `new_mode`, `old_type`, and `new_type`. Display one read-only information buffer explaining the old and new file types and modes without a text diff.
- Binary file: Required arguments are the change status, `old_path`, `new_path`, and available old and new object IDs or sizes. Display one read-only information buffer containing the paths, status, and available object or size information.
- Unmerged file: Required arguments are the path, available Git stage object IDs, and the current working-tree path. Display the current conflict buffer with its conflict markers and show `Unmerged file` in its winbar.
- Content load error: Required arguments are the path, attempted change status, and error message. Display one read-only information buffer containing the path, attempted operation, and error message.

"inline" mode:
files are shown as normal buffers with normal navigation. Status line for added/deleted/moved files should be present. Changed lines should be highlighted/marked with extmarks.

## Comments 
- Comments are shown as virtual text 
- Stale comments are marked in the virtual text 
- User can comment any part of the code in the review mode: changed and unchanged lines
- Comment editor is editable buffer for virtual temporary file. If comment text is deleted then comment is deleted 
- List of comments can be shown through special command
