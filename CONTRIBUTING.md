# Contributing to Kadr

Thanks for your interest in contributing to Kadr!

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/kadr.git`
3. Check out `develop`: `git checkout develop`
4. Create a feature branch off `develop`: `git checkout -b feat/your-feature`
5. Make your changes
6. Run tests: `swift test`
7. Commit with a [conventional commit](https://www.conventionalcommits.org/) message
8. Push and open a pull request **into `develop`** (not `main`)

## Branching Model

Kadr uses a two-branch flow:

- **`main`** — release-only. Every commit on `main` corresponds to a tagged release (e.g. `v0.1.0`, `v0.2.0`). Protected: no direct pushes, no force-pushes, linear history, CI must pass.
- **`develop`** — integration branch. All feature work is merged here. Protected: no direct pushes, no force-pushes, CI must pass.
- **`feat/*`, `fix/*`, `docs/*`, `chore/*`, `refactor/*`, `test/*`, `ci/*`** — short-lived topic branches cut from `develop` and PR'd back into `develop`.

### Release flow

1. When `develop` is ready for a release, finalize `CHANGELOG.md` and any release-prep doc updates on a `chore/vX.Y.Z-release` branch and merge it into `develop`.
2. Open a PR from `develop` into `main`.
3. **Merge with "Rebase and merge".** This replays each topic-PR commit onto `main`'s tip so `main` and `develop` share commit hashes — no divergence, no back-merge ceremony required.
4. Tag the release on `main`: `git tag -a v0.X.Y -m "v0.X.Y — <title>" && git push origin v0.X.Y`.
5. Create a GitHub Release from the tag using the `CHANGELOG.md` entry as the body.

Hotfixes branch from `main` directly (e.g. `fix/v0.X.Y-something`), merge into `main` first (rebase-and-merge), tag the patch, then PR the same fix into `develop` to keep the branches synchronized.

> **Historical note:** Releases **v0.1.0 through v0.3.0** used "Squash and merge" into `main`, which collapsed each release to a single commit. The granular per-PR commits remained on `develop`, so every subsequent release PR's rebase-and-merge would try to replay them onto `main` even though their content was already there as squashes — producing phantom conflicts. The fix-up at each release was a one-shot back-merge PR (`chore/sync-develop-with-main-vX.Y.Z`).
>
> For **v0.4.0** we tried to escape that cycle by back-merging `main` into `develop` after the v0.3.0 squash, expecting `develop` to then be a clean linear extension of `main`. It wasn't: the back-merge added the squash commit to develop's *graph* but didn't *remove* the original granular commits, so `main..develop` still contained 60+ already-on-main commits that re-conflicted on rebase.
>
> What actually worked: **reset `develop` to `main` and replay only the v0.4.0 commits** via `git cherry-pick`, then force-push. After that one-shot rewrite, `develop` is genuinely `main` + a handful of new commits.
>
> Going forward (v0.5.0+): each release PR rebase-and-merges cleanly without ceremony, and `develop` stays a clean linear extension of `main`. The history on `main` is mixed-shape: one squash commit per release through v0.3.0, then granular per-PR commits from v0.4.0 onward. That's the intentional cost of cleaning up.

## Development

**Requirements:**
- Xcode 16+ / Swift 6.0+
- macOS 13+

**Build:** `swift build`
**Test:** `swift test`

## Guidelines

- All public types must be `Sendable` (Swift 6 strict concurrency)
- No third-party dependencies — Kadr is AVFoundation-only
- Write tests for new functionality
- Follow existing code style and naming conventions
- Keep PRs focused — one feature or fix per PR

## Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` — new feature
- `fix:` — bug fix
- `test:` — adding or updating tests
- `docs:` — documentation only
- `refactor:` — code change that neither fixes a bug nor adds a feature
- `chore:` — maintenance tasks
- `ci:` — CI/CD changes

## Scope

Kadr follows a strict scope policy. Before starting work on a new feature, check [ROADMAP.md](ROADMAP.md) to see if it's planned and which version it targets. If your idea isn't on the roadmap, open an issue to discuss it first.

## License

By contributing, you agree that your contributions will be licensed under the Apache 2.0 License.
