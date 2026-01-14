# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.2] - 2026-01-14

### Changed
- Moved `TGReduxKitDemo` into `Examples/` directory for better project structure.
- Updated demo project dependencies to reference the local package correctly.
- Removed obsolete `CounterAppExample.swift`.

## [0.0.1] - 2026-01-11

### Added
- **Core**: Initial implementation of `Store`, `Middleware`, and `Reducer`.
- **SwiftUI**: Added `StoreProvider` (via `.provideStore`) and `Store.binding` helper.
- **Concurrency**: Full support for Swift 6 strict concurrency checks (`Sendable` conformance).
- **Documentation**:
  - Comprehensive API documentation (DocC).
  - Architecture diagram and usage guide in `README.md`.
  - Advanced usage examples (Async Middleware, Modular Reducers).
- **Examples**: Added `CounterAppExample` in `Examples/` directory.
- **CI/Quality**: Added `.swiftlint.yml` configuration.
