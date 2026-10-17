# Spec 001 Gap Review

Verdict: PASS. No blocking missing decisions or required spec patches.

Preserve explicit-side IDs as SHA-256 of the existing JSON tuple `{ file_id, side, line_start or 0, line_end or 0 }`. Represent an absent side explicitly without collapsing tuple slots. Reuse operation-specific availability validation so disallowed supplied versions do not qualify. Keep the change within the model and use real Git-loaded integration fixtures.

Reviewer session: `ses_eb72a05e1ffee42ZFRR9IsYmXE`.
