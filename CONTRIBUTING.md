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

> **Historical note:** Releases v0.1.0, v0.2.0, and v0.2.1 used "Squash and merge" into `main`, which collapsed each release to a single commit but caused the histories to diverge — every subsequent release PR hit phantom CHANGELOG conflicts that had to be resolved with a back-merge PR. Starting from **v0.3.0** we use rebase-and-merge to eliminate that ceremony permanently. As a result `git log main` will look slightly mixed-shape (squashed releases up to v0.2.1, granular thereafter); that's intentional.

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
