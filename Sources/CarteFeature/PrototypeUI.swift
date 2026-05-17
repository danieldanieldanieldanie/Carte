#if canImport(SwiftUI)
import SwiftUI
import CarteCore

@available(iOS 18.0, macOS 15.0, *)
public struct ComposePrototypeView: View {
    @State private var frontText = ""
    @State private var backText = ""

    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            Text("Carte")
                .font(.largeTitle)
            TextField("Front message", text: $frontText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            TextField("Back message (optional)", text: $backText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            RoundedRectangle(cornerRadius: 16)
                .fill(.brown.opacity(0.1))
                .overlay(Text("Long-press contact below to send"))
                .frame(height: 120)
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 12) {
                ForEach(["Ada", "Sam", "Kai", "Noor"], id: \.self) { name in
                    Text(name)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.thinMaterial)
                        .cornerRadius(12)
                }
            }
        }
        .padding()
    }
}
#endif
