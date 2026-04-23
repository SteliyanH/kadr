# Contributing to Kadr

Thanks for your interest in contributing to Kadr!

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/kadr.git`
3. Create a feature branch: `git checkout -b feat/your-feature`
4. Make your changes
5. Run tests: `swift test`
6. Commit with a [conventional commit](https://www.conventionalcommits.org/) message
7. Push and open a pull request

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
