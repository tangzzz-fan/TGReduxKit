import SwiftUI
import TGReduxKit

// 1. State
struct CounterState {
    var count: Int = 0
    var isLoading: Bool = false
    var errorMessage: String?
}

// 2. Action
enum CounterAction {
    case increment
    case decrement
    case incrementAsync
    case setLoading(Bool)
    case setError(String?)
}

// 3. Reducer
let counterReducer: Reducer<CounterState, CounterAction> = { state, action in
    switch action {
    case .increment:
        state.count += 1
    case .decrement:
        state.count -= 1
    case .setLoading(let loading):
        state.isLoading = loading
    case .setError(let error):
        state.errorMessage = error
    case .incrementAsync:
        break // Handled by middleware
    }
}

// 4. Middleware
let asyncMiddleware: Middleware<CounterState, CounterAction> = { store, action, next in
    next(action)
    
    if case .incrementAsync = action {
        Task {
            await MainActor.run { store.dispatch(.setLoading(true)) }
            
            // Simulate network delay
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            await MainActor.run {
                store.dispatch(.increment)
                store.dispatch(.setLoading(false))
            }
        }
    }
}

// 5. View
struct CounterView: View {
    @Environment(Store<CounterState, CounterAction>.self) var store
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Count: \(store.state.count)")
                .font(.largeTitle)
            
            if store.state.isLoading {
                ProgressView()
            }
            
            HStack {
                Button("-") { store.dispatch(.decrement) }
                Button("+") { store.dispatch(.increment) }
            }
            
            Button("Async +1") {
                store.dispatch(.incrementAsync)
            }
        }
        .padding()
    }
}

// 6. App Entry
@main
struct CounterApp: App {
    let store = Store(
        initialState: CounterState(),
        reducer: counterReducer,
        middlewares: [asyncMiddleware]
    )
    
    var body: some Scene {
        WindowGroup {
            CounterView()
                .provideStore(store)
        }
    }
}
