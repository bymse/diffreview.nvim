# Repository Guidelines

## Test Naming

Name tests in lowercase snake_case using this pattern:

```text
method_should_expected_behavior_when_condition
```

Example: `rev_parse_should_return_error_when_repository_has_no_commits`.

## Test Design

- Test observable behavior through public interfaces and real editor/Git fixtures; do not assert component internals or incidental diagnostic wording.
- Do not mock, replace, or intercept components, Neovim APIs, or notifications to force or observe behavior. If behavior cannot be observed externally, omit that test.
- Split large test modules into focused files by behavior (for example, revision resolution, filesystem errors, and cancellation).
- Integration tests exercise module interfaces, not user interactions: do not send editor keys or replicate user behavior. Put key-driven editor flows in functional tests; add an internal interface when integration coverage needs one.

## Running Tests

Run a complete category with:

```sh
just test-unit
just test-integration
just test-functional
```

Run one test by passing its exact name:

```sh
just test-unit parse_diff_output_should_parse_single_file
just test-integration rev_parse_should_return_error_when_repository_has_no_commits
just test-functional plugin_should_display_hello_world_when_loaded
```

Run every category with `just test`.

## Required Verification

Before returning control to the user or creating a commit:

1. Run LuaLS checks for the affected Lua code and fix every reported issue.
2. Run `just format` after LuaLS checks and ensure `just format-check` passes.
3. Run tests for the affected part of the codebase. Run the specific test when one case is affected; run all tests with `just test` when more than one case is affected.

## Lua Type Annotations

Add LuaLS annotations to every public function. Document all parameters, callback signatures, and return values with `---@param` and `---@return`.

Do not annotate local variables with primitive types such as strings, numbers, or booleans. Add local variable annotations only for complex types or when LuaLS cannot infer a complex type correctly.
