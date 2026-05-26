import SwiftUI

/// Places Clear and Done buttons directly above the keyboard
/// using SwiftUI's native keyboard toolbar placement.
struct KeyboardToolbarModifier: ViewModifier {
    var onClear: () -> Void
    var onDone: () -> Void

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Clear") { onClear() }
                        .foregroundStyle(Color.accentColor)
                    Button("Done") { onDone() }
                        .fontWeight(.medium)
                        .foregroundStyle(Color.accentColor)
                }
            }
    }
}

extension View {
    func clearDoneToolbar(onClear: @escaping () -> Void, onDone: @escaping () -> Void) -> some View {
        modifier(KeyboardToolbarModifier(onClear: onClear, onDone: onDone))
    }
}
