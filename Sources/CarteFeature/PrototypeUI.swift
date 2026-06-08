#if canImport(SwiftUI)
import SwiftUI

@available(iOS 18.0, macOS 15.0, *)
public struct ComposePrototypeView: View {
    private let state: CarteAppState

    @State private var frontText = ""
    @State private var backText = ""
    @State private var sendBanner = ""

    public init(state: CarteAppState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text("Carte")
                .font(.largeTitle)

            TextField("Front message", text: $frontText, axis: .vertical)
                .textFieldStyle(.roundedBorder)

            TextField("Back message (optional)", text: $backText, axis: .vertical)
                .textFieldStyle(.roundedBorder)

            if !sendBanner.isEmpty {
                Text(sendBanner)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text("Press and hold a contact to send")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 12) {
                ForEach(state.contacts) { contact in
                    Text(contact.displayName)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.thinMaterial)
                        .cornerRadius(12)
                        .onLongPressGesture {
                            Task {
                                do {
                                    state.draft.frontText = frontText
                                    state.draft.backText = backText
                                    try await state.sendDraft(to: contact)
                                    frontText = ""
                                    backText = ""
                                    sendBanner = "Sent to \(contact.displayName)"
                                } catch {
                                    sendBanner = "Send failed: \(error.localizedDescription)"
                                }
                            }
                        }
                }
            }
        }
        .padding()
    }
}
#endif
