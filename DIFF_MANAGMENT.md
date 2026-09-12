## Diff management 
Open questions:

- how to collect changed files 
- in which format should be changes to display them in nvim
- how to represent stable contract between parts of the system

Hints from requirements:
- Start a review against a branch or commit. A branch uses its merge base with the current branch; a commit is used as the exact baseline.
- Build one aggregate comparison from the baseline to the current local state, including every Git change category such as additions, deletions, renames, binary files, submodules, and untracked files.
- Build one aggregate comparison from the baseline to the current local state, including every Git change category such as additions, deletions, renames, binary files, submodules, and untracked files.
- The comparison is an aggregate result; committed, staged, unstaged, and untracked layers are not reviewed separately.
- Branch comparisons resolve the merge base and compare it with the combined committed, index, working-tree, and untracked result.
- Comparison data retains rename, deletion, mode, binary, old/new path, additions/deletions, object ID, and parsed hunk metadata needed by views, comments, refresh reconciliation, and remote publishing.

### Implementation 

**What should be implemented:**
1. collect changed files from git 
2. parse changes 
3. enrich them with required data 
4. map them to an expected model

**How to compare?**
1. Always include commited changes, staged changes, unstaged changes, untracked files 
2. If no args provided then compare HEAD with merge-base with default branch 
3. If branch name is provided then compare HEAD with merge-base with specified branch 
4. If commit is provided then compare HEAD with specified commit 
5. If two branches/commits are provided then compare them 

**How to collect changes:** 
1. When one argument is provided, compare it with the current tracked working state and collect untracked files separately:
   - `git diff --raw -z -M -C <from>`
   - `git ls-files --others --exclude-standard -z`
2. When two arguments are provided, compare the two Git revisions:
   - `git diff --raw -z -M -C <from> <to>`

**Output format:**
1. :<old-mode> <new-mode> <old-oid> <new-oid> <status>\0<path>\0 
2. :<old-mode> <new-mode> <old-oid> <new-oid> R<score> \0<old-path>\0<new-path>\0

### Module interface 

1. Collect changes, accept required args from "how to compare". returns data structure with props: 
  1.1. old and new path
  1.2. state enum: modified, added, deleted, file mode changed, copy, rename, type change (symlink related), unmerged, error
  1.3. opaque identifier to fetch content for old version
2. Get content for old version using identifier from 1.3

### File identity

- Use `stored:<old-path>` for files that existed in the comparison baseline. Modified, deleted, renamed, and type-changed files retain this identity even when their current path changes.
- Use `new:<new-path>` for files introduced after the baseline, including added, copied, and untracked files.
- A file ID identifies an entry across review state and UI refreshes. It is separate from an object ID, which identifies content and is used to load an old version.
