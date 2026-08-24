import Observation

/// The minimal, view-facing surface shared by `Store` and `ScopedStore`.
///
/// `StoreType` intentionally covers only synchronous state access and action dispatch so SwiftUI
/// views can stay agnostic to whether they receive a root store or a scoped store.
///
/// Task lifecycle APIs such as `runTask`, `debounce`, `throttle`, and timeout/retry helpers remain
/// root-`Store` capabilities. This keeps async side effects anchored at the root state boundary
/// instead of letting feature-scoped views or stores own independent task registries.
@MainActor
public protocol StoreType<State, Action>: AnyObject, Observable {
    associatedtype State
    associatedtype Action

    var state: State { get }
    func dispatch(_ action: Action)
}
