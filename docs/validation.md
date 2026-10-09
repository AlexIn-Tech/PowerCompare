# Development preview validation

Validated on 2026-10-09 using PowerShell 7.4.13 on Debian Linux, Pester 5.7.1, and PSScriptAnalyzer 1.24.0.

- `scripts/Test.ps1 -Coverage`: 92 passed, 0 failed, 2 Windows-only skips.
- Core command coverage: 92.78%, 748 analyzed commands across five engine files. This is command coverage, not a guarantee of correctness.
- PSScriptAnalyzer Error severity and `git diff --check`: clear.
- Independent whole-branch review identified copy-cancellation audit loss and unreadable-subtree classification defects. Both were reproduced as failing tests and fixed with a green full suite.
- Newline-only navigation was also corrected with a failing row-level fixture; line-ending metadata is visible in the text grid.

## Windows acceptance

[Windows CI run 37927221934](https://github.com/AlexIn-Tech/PowerCompare/actions/runs/37927221934) passed on the reviewed application/test snapshot under Windows PowerShell 5.1 and PowerShell 7: each runtime reported 92 passed, 0 failed, 2 nonapplicable skips, 92.38% core command coverage, and clean analyzer Error checks. The skips cover the non-Windows launcher requirement and case-sensitive-filesystem fixture; WPF tests ran. The initial Windows-only parser incompatibility and two test-portability failures were reproduced in CI and corrected before this passing run.

Windows CI runs both Windows PowerShell 5.1 and PowerShell 7. Its STA tests load the main, text and copy-preview XAML views, show the main window, invoke Compare twice through dispatcher events, and verify the bound collection remains stable. Skipped Windows tests on Linux are not passing Windows acceptance.

Interactive acceptance remains open:

- Compare large trees, cancel active hashing, change roots and compare again; verify the window responds and stale results do not replace the current comparison.
- Open changed text, navigate ordinary and newline-only differences, cancel loading, and verify keyboard focus and scroll behavior.
- Preview both copy directions, cancel the dialog, confirm a copy, and verify backups and the completed-operation log after cancellation.
- Save/load sessions and export each report format through the dialogs.
- Resize each window and exercise keyboard navigation and high-DPI display settings.

## Scope

This implementation is a development preview of the approved WPF foundation plus text comparison, guarded selected-file copies, local sessions, and reports. Full BC5 Pro Windows parity is not complete. The feature ledger records all remaining work and differentiates Planned, Partial, Implemented, and Accepted. No feature is marked Accepted solely from this Linux run.

## Decisions carried from execution

- The new local clone on `feature/wpf-powercompare` is the isolated working checkout; the original main branch is not modified by implementation.
- Foundation adapters use built-in .NET. Optional external protocol/format adapters remain a separate policy decision; no dependency is silently installed by the app.
- Genuine Windows validation stays explicit; Linux or XML-only evidence cannot establish WPF readiness.
- Newline-navigation finding was regraded Important because otherwise actual file differences cannot be located in the comparison view; it is fixed rather than deferred.
