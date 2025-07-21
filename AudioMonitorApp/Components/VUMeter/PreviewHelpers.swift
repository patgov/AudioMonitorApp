    //
    //  PreviewHelpers.swift.swift
    //  AudioMonitorApp
    //
    //  Created by Pat Govan on 6/9/25.
    //

import SwiftUI

    /// Utility wrapper to enable @Binding in SwiftUI previews
struct StatefulPreviewWrapper<Value: Equatable, Content: View>: View {
    @State private var value: Value
    var content: (Binding<Value>) -> Content
    
    init(_ initialValue: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: initialValue)
        self.content = content
    }
    
    var body: some View {
        content($value)
    }
}

struct StatefulPreviewWrapper_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            StatefulPreviewWrapper(0.5) { binding in
                StyledAnalogVUMeterView(leftLevel: Float(binding.wrappedValue), rightLevel: Float(binding.wrappedValue))
                    .frame(width: 300, height: 200)
                    .padding()
            }
        }
    }
}
