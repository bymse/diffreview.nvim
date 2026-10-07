# Architecture 

Strucutre of the plugin.

Key modules:
1. Interactions with git. See DIFF_MANAGMENT.md 
2. UI 
    2.1. quickfix list with files for the review 
    2.2. Hierarchy of files 
    2.3. Diff view + inline comments 
    2.4. Inline view + inline comments 
    2.5. List of comments 
    2.6. Comments editor 
3. Comments storage + publishing
4. Orchestration 

## MVC

**Model:**
1. Review state 
2. Comments state 
3. Operations:  
  3.1. Mark file as reviewed 
  3.2. Add/edit/delete comments 
  3.3. Start review
  3.4. Publish comments 
  3.5. Load files for the review 

**View:** see @UI.md 

**Controller:** handle commands from nvim ui and pass them between model and ui

**Layout:**
1. diffreview/init.lua: setup, public API, and user command registration
2. diffreview/autocmds.lua: events registration
3. diffreview/review.lua: review session controller and orchestration
4. diffreview/storage.lua: persistence
5. diffreview/diffs: collection of diffs, diff loading, refresh, ...
6. diffreview/ui: interactions with nvim ui
7. diffreview/comments: operations on comments

## Testing 

Model: inegration tests for all except for comments publishing to remote. Integration tests should create real temp git repository and prepare required data there 

View + controller: e2e tests using downloaded nvim 
