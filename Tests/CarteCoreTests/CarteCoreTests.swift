import XCTest
@testable import CarteCore
@testable import CarteFeature

final class CarteCoreTests: XCTestCase {
    func testCardRequiresOneOrTwoSides() {
        let sender = UUID()
        let card = Card(
            senderID: sender,
            senderDisplayName: "Ana",
            sides: [.init(index: .front, content: .text("hello"))]
        )
        XCTAssertEqual(card.sides.count, 1)
    }

    func testComposerCreatesBackSideWhenProvided() {
        let composer = CardComposer()
        let card = composer.composeText(senderID: UUID(), senderDisplayName: "A", text: "Front", back: "Back")
        XCTAssertTrue(card.hasBackSide)
        XCTAssertEqual(card.sides.count, 2)
    }

    func testInMemoryTransportSendEraseInbox() async throws {
        let transport = InMemoryCardTransport()
        let recipient = UUID()
        let card = Card.draftText(senderID: UUID(), senderDisplayName: "Lia", text: "Hi")

        let deliveries = try await transport.send(card: card, to: [recipient])
        XCTAssertEqual(deliveries.count, 1)

        var inbox = try await transport.inbox(for: recipient)
        XCTAssertEqual(inbox.count, 1)

        try await transport.erase(deliveryID: deliveries[0].id, for: recipient)
        inbox = try await transport.inbox(for: recipient)
        XCTAssertEqual(inbox.count, 0)
    }

    @MainActor
    func testAppStateSendAndRefreshInbox() async throws {
        let me = UUID()
        let transport = InMemoryCardTransport()
        let state = CarteAppState(
            currentUserID: me,
            currentUserDisplayName: "Me",
            contacts: [.init(id: me, displayName: "Me")],
            transport: transport
        )

        state.draft.frontText = "Hello"
        try await state.sendDraft(to: state.contacts[0])
        try await state.refreshInbox()

        XCTAssertEqual(state.inbox.count, 1)
    }
}
