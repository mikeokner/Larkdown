# Larkdown contributor instructions

Larkdown is an open source macOS app for editing and previewing local Markdown
files. Preserve native document behavior, source fidelity, and responsiveness.
Assume tracked content is public. Keep credentials and personal task state out
of commits. Write user-facing documentation for app users and contributor
documentation for developers.

## Commands

Run commands from the repository root. See [Developing Larkdown](DEVELOPING.md)
for setup and release tooling; inspect scripts and CI for their current behavior.

| Command | Purpose |
| --- | --- |
| `scripts/doctor.sh` | Inspect the local toolchain. |
| `swift test --package-path Packages/LarkdownCore` | Run package tests during focused iteration. |
| `scripts/test.sh` | Run package tests and native app tests. |
| `scripts/test.sh --ui-tests` | Also run UI tests; needs an unlocked desktop. |
| `scripts/build.sh` | Build the app in Debug by default. |
| `CONFIGURATION=Release scripts/build.sh` | Check the direct-distribution configuration. |

After application implementation changes, run `scripts/test.sh` and
`scripts/build.sh`. If you change distribution settings or packaging, also
check the Release configuration. After window, menu, or editor interaction
changes, also run `scripts/test.sh --ui-tests` if a desktop session is
available. For documentation-only changes, check references and diff hygiene;
an application rebuild is unnecessary. Report blocked or unrun checks
explicitly. Do not run builds and tests concurrently.

## Architecture and changes

- Put reusable non-UI behavior in `Packages/LarkdownCore`: parsing, rendering,
  preview HTML, encoding, line endings, and shared models.
- Keep app lifecycle, document windows, menus, AppKit/WebKit views,
  entitlements, signing, and the Sparkle updater in the app target.
- Follow existing Swift and shell patterns. Avoid unnecessary Xcode project
  edits. For large project, signing, or capability changes, use Xcode unless
  there is a clear reason for a targeted project-file edit.
- Keep Markdown source authoritative. Do not silently rewrite user content.
- Remove functionality made obsolete by a change; avoid parallel legacy paths.
- Prefer build checks and integration or end-to-end tests. Add focused package
  tests when they exercise important behavior those checks cannot cover.
- Do not change `README.md` unless the user asks for README changes.
- Distinguish existing implementation from desired behavior and unverified
  assumptions. Recheck old review findings before acting on them.

## Optional private workflow

If `.agent-local/WORKFLOW.md` exists, read and follow it before starting work.
It defines local planning and delegation conventions. Keep personal plans,
handoffs, and investigation evidence inside `.agent-local/` and out of public
issues, PRs, and commits. Do not force-add ignored files.

The repository must remain usable without private context or custom agents.
When local context is absent, use the user's request, tracked documentation,
and current code.
