# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is RepoBar?

RepoBar is a macOS menu bar app (SwiftUI + AppKit NSMenu) that shows GitHub repo status, CI, releases, activity, and local Git state. It also has an iOS companion app (`RepoBariOS/`) and a CLI (`repobarcli`).

## Build & Development Commands

Requires: pnpm v10+, Swift 6.2, Xcode 26. Run `pnpm install` once for script deps.

| Command | Purpose |
|---|---|
| `pnpm check` | Format + lint + test (run before PRs) |
| `pnpm test` | Run Swift Testing tests via `Scripts/test.sh` |
| `pnpm test -- --filter <pattern>` | Run specific tests |
| `pnpm build` | Debug build (`swift build`) |
| `pnpm start` / `pnpm restart` | Rebuild + codesign + relaunch the menu bar app |
| `pnpm stop` | Kill the running app |
| `pnpm format` | Run swiftformat |
| `pnpm lint` | Run swiftlint |
| `pnpm check:coverage` | Coverage run (isolated `.build/coverage` dir) |
| `pnpm codegen` | Apollo GraphQL codegen (only with schema access configured) |

Always use pnpm scripts rather than raw `swift build`/`swift test` — they set cache paths and handle codesigning.

## Architecture

Three SwiftPM targets share a common core:

- **RepoBarCore** — shared library with no UI dependencies. Contains GitHub API clients (GraphQL via Apollo + REST), data models (`Repository`, `UserIdentity`, `RepoRecentItems`, etc.), auth token storage, local project scanning, and settings/preferences.
- **RepoBar** — the macOS menu bar app. `RepoBarApp` is the entry point. `AppState` (split across `AppState+*.swift` extensions) is the central `@Observable` model driving the status bar menu. `StatusBar/` builds NSMenu hierarchies via `StatusBarMenuManager` and `StatusBarMenuBuilder`. SwiftUI views live in `Views/` and `Settings/`.
- **repobarcli** — command-line tool using Commander for argument parsing and Swiftdansi for terminal colors. Reuses RepoBarCore for API access.

### Key patterns

- `AppState` extensions partition concerns: `+Auth`, `+Refresh`, `+Activity`, `+Contributions`, `+Visibility`.
- The menu bar uses AppKit `NSMenu`/`NSMenuItem` with SwiftUI views hosted via `MenuItemHosting`. `StatusBarMenuBuilder` assembles menu structure; coordinators (`RecentListMenuCoordinator`, `ActivityMenuCoordinator`, etc.) manage subsections.
- GitHub API: `GitHubClient` handles GraphQL queries; `GitHubRestAPI` handles REST endpoints. Both live in `RepoBarCore/API/`.
- Generated GraphQL types go in `Sources/RepoBar/API/Generated` — never hand-edit these.
- OAuth uses PKCE flow via AppAuth; tokens stored in macOS Keychain.
- Auto-updates via Sparkle; appcast at `appcast.xml`.

## Code Style

- **swiftformat**: 4-space indent, `--commas inline`, `--wraparguments before-first`, `--wrapcollections before-first`, `--self insert`, no semicolons.
- **swiftlint**: many length/complexity rules disabled (see `.swiftlint.yml`). Opt-in: `empty_string`, `explicit_init`, `redundant_nil_coalescing`, `implicitly_unwrapped_optional`. Analyzer rules: `unused_declaration`, `unused_import`.
- Excludes: `Sources/RepoBar/API/Generated` from both tools.
- Use `@Observable` (not `ObservableObject`). Prefer models directly in views; only add view models when they provide real derived value.
- Swift 6.2 strict concurrency enabled across all targets.

## Testing

- Framework: Swift Testing (not XCTest). Name suites `<Thing>Tests`, functions `test_<behavior>()`.
- Test targets: `RepoBarTests` (app logic) and `repobarcliTests` (CLI, with `Fixtures/` resources).

## Commit Style

Short, imperative, present tense. Optional scoped prefixes: `menu:`, `settings:`, `tests:`, `fix:`, `docs:`, `style:`, `chore:`. No trailing period.

## Version

Canonical version lives in `version.env` (`MARKETING_VERSION` and `BUILD_NUMBER`).
