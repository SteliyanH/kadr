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

1. When `develop` is ready for a release, open a PR from `develop` into `main`.
2. Once merged, tag the release on `main`: `git tag v0.X.0 && git push origin v0.X.0`.
3. Update `CHANGELOG.md` and `ROADMAP.md`.

Hotfixes for a shipped release branch from `main`, merge into `main` (with a tagged patch release), then are back-merged into `develop`.

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
