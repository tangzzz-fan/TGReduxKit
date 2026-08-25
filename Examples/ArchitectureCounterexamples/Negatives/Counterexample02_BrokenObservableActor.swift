#if COUNTEREXAMPLE_COMPILE_FAIL
import Observation
import SwiftUI

/// 反例 2：`@Observable` actor + `nonisolated` state 无法形成正确观察/写入模型。
@Observable
final actor BrokenObservableStore {
    nonisolated let state: Int = 0

    func updateState() {
        // expected-error: 'state' is a 'let' constant / isolation conflict
        // state = 42
        _ = state
    }
}

@Observable
final class StateBox: @unchecked Sendable {
    var value: Int = 0
}

@Observable
final actor BrokenObservableStore2 {
    nonisolated let state: StateBox = StateBox()

    func updateState() {
        state.value = 42
    }
}

struct Counterexample02View: View {
    let store = BrokenObservableStore2()

    var body: some View {
        Text("\(store.state.value)")
            .onAppear {
                // expected-error: Expression is 'async' but is not marked with 'await'
                store.updateState()
            }
    }
}
#endif
