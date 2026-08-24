import Observation

@MainActor
public protocol StoreType<State, Action>: AnyObject, Observable {
    associatedtype State
    associatedtype Action

    var state: State { get }
    func dispatch(_ action: Action)
}
