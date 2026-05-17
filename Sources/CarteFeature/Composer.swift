import Foundation
import CarteCore

public struct CardComposer: Sendable {
    public init() {}

    public func composeText(senderID: UUID, senderDisplayName: String, text: String, back: String? = nil) -> Card {
        var sides: [CardSide] = [.init(index: .front, content: .text(text))]
        if let back, !back.isEmpty {
            sides.append(.init(index: .back, content: .text(back)))
        }
        return Card(senderID: senderID, senderDisplayName: senderDisplayName, sides: sides)
    }
}
