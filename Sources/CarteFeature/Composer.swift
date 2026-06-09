import Foundation
import CarteCore

public struct CardComposer: Sendable {
    public init() {}

    public func composeText(senderID: UUID, senderDisplayName: String, text: String, back: String? = nil) -> Card {
        var sides = [CardSide(index: .front, content: .text(text.trimmingCharacters(in: .whitespacesAndNewlines)))]
        if let back, !back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sides.append(.init(index: .back, content: .text(back.trimmingCharacters(in: .whitespacesAndNewlines))))
        }
        return Card(senderID: senderID, senderDisplayName: senderDisplayName, sides: sides)
    }

    public func compose(
        senderID: UUID,
        senderDisplayName: String,
        front: CardSide.Content,
        back: CardSide.Content? = nil
    ) -> Card {
        var sides = [CardSide(index: .front, content: front)]
        if let back {
            sides.append(CardSide(index: .back, content: back))
        }
        return Card(senderID: senderID, senderDisplayName: senderDisplayName, sides: sides)
    }
}
