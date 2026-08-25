#if COUNTEREXAMPLE_COMPILE_FAIL
import SwiftUI

/// 反例 4：`dispatch` 返回 `Task` —— View 同步上下文无法正确拥有生命周期。
actor TaskReturningStore {
    func dispatch(_ action: String) -> Task<Void, Never> {
        Task {
            _ = action
        }
    }
}

struct Counterexample04View: View {
    let store = TaskReturningStore()

    var body: some View {
        Button("Action") {
            // expected-error: Expression is 'async' but is not marked with 'await'
            let task = store.dispatch("action")
            _ = task
        }
    }
}
#endif
