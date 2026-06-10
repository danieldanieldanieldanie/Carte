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

    func testInMemoryTransportArchiveRemovesCardFromTransit() async throws {
        let transport = InMemoryCardTransport()
        let recipient = UUID()
        let card = Card.draftText(senderID: UUID(), senderDisplayName: "Lia", text: "Hi")
        let delivery = try await transport.send(card: card, to: [recipient]).first!

        try await transport.archive(deliveryID: delivery.id, for: recipient)
        let all = try await transport.inbox(for: recipient)

        XCTAssertEqual(all.count, 0)
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

    @MainActor
    func testDismissToArchiveStoresLocallyAndClearsTransit() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = JSONProfileStore(directory: directory)
        let me = UUID()
        let transport = InMemoryCardTransport()
        let state = CarteAppState(
            profile: UserProfile(id: me, displayName: "Me"),
            contacts: [.init(id: me, displayName: "Me")],
            transport: transport,
            store: store
        )

        state.draft.frontText = "A card to keep"
        try await state.sendDraft(to: state.contacts[0])
        try await state.refreshInboxAndArchive()
        let delivery = try XCTUnwrap(state.inbox.first)

        try await state.dismissToArchive(delivery)

        XCTAssertEqual(state.inbox.count, 0)
        XCTAssertEqual(state.archive.count, 1)
        XCTAssertEqual(state.archive[0].card.sides.first?.content, .text("A card to keep"))
        let remainingTransit = try await transport.inbox(for: me)
        let persistedArchive = try await store.loadArchive()
        XCTAssertEqual(remainingTransit.count, 0)
        XCTAssertEqual(persistedArchive.count, 1)
    }

    @MainActor
    func testAppStateRejectsEmptyDraft() async throws {
        let me = UUID()
        let state = CarteAppState(
            currentUserID: me,
            currentUserDisplayName: "Me",
            contacts: [.init(id: me, displayName: "Me")],
            transport: InMemoryCardTransport()
        )

        do {
            try await state.sendDraft(to: state.contacts[0])
            XCTFail("Expected empty draft to fail")
        } catch let error as CarteUserFacingError {
            XCTAssertEqual(error.errorDescription, CarteUserFacingError.emptyDraft.errorDescription)
        }
    }

    func testContactBookAddsInviteCodeContact() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = JSONProfileStore(directory: directory)
        let book = ContactBook(store: store)
        let friendID = UUID()

        let contacts = try await book.addContact(displayName: "Mina", inviteCode: friendID.uuidString, to: [])

        XCTAssertEqual(contacts, [Contact(id: friendID, displayName: "Mina")])
        let persisted = try await store.loadContacts()
        XCTAssertEqual(persisted, contacts)
    }
}
