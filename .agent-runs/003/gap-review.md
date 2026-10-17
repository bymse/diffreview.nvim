# Spec 003 Gap Review

Initial verdict: BLOCK. Clarifications required for same-target request precedence after diff/origin loss, native forced-quit ownership, caller responsibility for whole-file provenance, and source-window recovery while the editor is focused.

Spec/context patched: validate options container and target shape before same-target reuse; ignore replacement payload fields and current-presentation lookup when reusing a draft. Native `:q!` explicitly discards, while non-discarding hide may retain a modified buffer. Whole-file membership and supplied-side availability are caller preconditions. Include side-by-side recovery protection and public regression coverage preserving modified drafts after source-pane loss. Preserve display focus behavior.

Reviewer session: `ses_eb7177747ffeysc2QqUYK6eoq5`. Re-review verdict: PASS. No material ambiguity or required patches remain. Native write failure, discard-versus-hide lifecycle handling, and source recovery are implementation risks with explicit regression requirements.
