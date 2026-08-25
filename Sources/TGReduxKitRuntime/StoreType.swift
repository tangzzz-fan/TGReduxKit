import Observation
import TGReduxKitCore

/// Minimal surface for Views. Effect scheduling / cancellation stay on root `Store`.
@MainActor
public protocol StoreType<State, Action>: AnyObject, Observable {
    associatedtype State
    associatedtype Action: Sendable

    var state: State { get }
    func dispatch(_ action: Action)
}
