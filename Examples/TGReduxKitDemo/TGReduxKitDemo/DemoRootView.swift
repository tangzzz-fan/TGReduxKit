import SwiftUI

/// Pick which Composition Root style to run — both share the same Shopping UI / Middleware factories.
struct DemoRootView: View {
    enum CompositionStyle: String, CaseIterable, Identifiable {
        case manual = "Manual (no Factory)"
        case factory = "FactoryKit"

        var id: String { rawValue }
    }

    @State private var style: CompositionStyle?

    var body: some View {
        Group {
            if let style {
                switch style {
                case .manual:
                    ManualDIShoppingAppView()
                case .factory:
                    FactoryDIShoppingAppView()
                }
            } else {
                NavigationStack {
                    List(CompositionStyle.allCases) { item in
                        Button(item.rawValue) {
                            style = item
                        }
                    }
                    .navigationTitle("Composition Root")
                    .safeAreaInset(edge: .bottom) {
                        Text(
                            "Both paths call the same make*Middleware factories. Factory only changes how services are resolved at the door."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding()
                    }
                }
            }
        }
    }
}
