# Development preview validation

Validated on 2026-10-09 using PowerShell 7.4.13 on Debian Linux, Pester 5.7.1, and PSScriptAnalyzer 1.24.0.

- `scripts/Test.ps1 -Coverage`: 92 passed, 0 failed, 2 Windows-only skips.
- Core command coverage: 92.76%, 746 analyzed commands across five engine files. This is command coverage, not a guarantee of correctness.
- PSScriptAnalyzer Error severity and `git diff --check`: clear.
- Independent whole-branch review identified copy-cancellation audit loss and unreadable-subtree classification defects. Both were reproduced as failing tests and fixed with a green full suite.
- Newline-only navigation was also corrected with a failing row-level fixture; line-ending metadata is visible in the text grid.

## Windows acceptance

Windows PowerShell 5.1, WPF view loading, actual dispatcher events, dialog bindings, resize/keyboard behavior, and interactive copy/text workflows require Windows evidence. Windows CI is configured for both supported runtimes and includes STA view loading and repeated Compare clicks. Skipped Windows tests on Linux are not passing Windows acceptance.

## Scope

This implementation is a development preview of the approved WPF foundation plus text comparison, guarded selected-file copies, local sessions, and reports. Full BC5 Pro Windows parity is not complete. The feature ledger records all remaining work and differentiates Planned, Partial, Implemented, and Accepted. No feature is marked Accepted solely from this Linux run.

## Decisions carried from execution

- The new local clone on `feature/wpf-powercompare` is the isolated working checkout; the original main branch is not modified by implementation.
- Foundation adapters use built-in .NET. Optional external protocol/format adapters remain a separate policy decision; no dependency is silently installed by the app.
- Genuine Windows validation stays explicit; Linux or XML-only evidence cannot establish WPF readiness.
- Newline-navigation finding was regraded Important because otherwise actual file differences cannot be located in the comparison view; it is fixed rather than deferred.
