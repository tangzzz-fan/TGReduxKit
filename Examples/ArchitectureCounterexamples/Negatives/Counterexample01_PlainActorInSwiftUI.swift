#if COUNTEREXAMPLE_COMPILE_FAIL
import SwiftUI

/// 反例 1：非 MainActor 的 actor 不能作为 SwiftUI 同步状态根。
/// 启用：`-DCOUNTEREXAMPLE_COMPILE_FAIL` 加入临时 target 后应出现隔离错误。
actor PlainActorStore<State: Sendable, Action: Sendable> {
    var state: State

    init(initialState: State) {
        self.state = initialState
    }

    func dispatch(_ action: Action) {
        _ = action
    }
}

struct Counterexample01View: View {
    let store = PlainActorStore<Int, String>(initialState: 0)

    var body: some View {
        VStack {
            // expected-error: Actor-isolated property 'state' can not be referenced…
            Text("\(store.state)")

            Button("Increment") {
                // expected-error: Actor-isolated instance method 'dispatch'…
                store.dispatch("increment")
            }
        }
    }
}
#endif
