# Contributing to TGReduxKit

Thank you for considering contributing to TGReduxKit!

## Development Process

1.  **Fork and Clone**: Fork the repository and clone it locally.
2.  **Branching**: Create a feature branch for your changes (`git checkout -b feature/amazing-feature`).
3.  **Coding Standards**:
    - Follow Swift Design Guidelines.
    - Ensure code passes SwiftLint checks.
    - Write unit tests for new functionality.
4.  **Documentation**: Update public API documentation if necessary.

## Release & Changelog Guide

We follow [Semantic Versioning](https://semver.org/) and [Keep a Changelog](https://keepachangelog.com/).

### Updating CHANGELOG.md

When you make a change, please update the `[Unreleased]` section of `CHANGELOG.md`. If the section does not exist, create it at the top of the file.

Categories:
- `Added` for new features.
- `Changed` for changes in existing functionality.
- `Deprecated` for soon-to-be removed features.
- `Removed` for now removed features.
- `Fixed` for any bug fixes.
- `Security` in case of vulnerabilities.

### Release Workflow (Maintainers)

1.  **Update Changelog**:
    - Move content from `[Unreleased]` to a new version section (e.g., `## [0.0.2] - YYYY-MM-DD`).
    - Update the comparison links at the bottom of the file (if applicable).
2.  **Bump Version**:
    - No `Info.plist` in SPM packages, but ensure Git tag matches.
3.  **Commit**: Commit the changelog changes.
4.  **Tag**: Create a git tag for the release.
    ```bash
    git tag 0.0.2
    git push origin 0.0.2
    ```
