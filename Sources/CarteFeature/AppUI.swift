#if canImport(SwiftUI) && canImport(Combine) && os(iOS)
import CarteCore
import SwiftUI
#if canImport(PhotosUI)
import PhotosUI
#endif
#if canImport(PencilKit)
import PencilKit
#endif

@available(iOS 18.0, macOS 15.0, *)
public struct CarteRootView: View {
    @ObservedObject private var state: CarteAppState

    public init(state: CarteAppState) {
        self.state = state
    }

    public var body: some View {
        Group {
            if state.profile == nil {
                OnboardingView(state: state)
            } else {
                TabView {
                    ComposeScreen(state: state)
                        .tabItem { Label("Write", systemImage: "square.and.pencil") }
                    InboxScreen(state: state)
                        .tabItem { Label("Tray", systemImage: "tray") }
                    ArchiveScreen(state: state)
                        .tabItem { Label("Archive", systemImage: "archivebox") }
                    SettingsScreen(state: state)
                        .tabItem { Label("Me", systemImage: "person.crop.circle") }
                }
                .tint(.primary)
                .task { await state.bootstrap() }
            }
        }
        .minimalCarteChrome()
    }
}

@available(iOS 18.0, macOS 15.0, *)
private struct OnboardingView: View {
    @ObservedObject var state: CarteAppState
    @State private var displayName = ""

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            VStack(spacing: 8) {
                Text("Carte")
                    .font(.system(size: 42, weight: .regular, design: .serif))
                Text("small cards for people you know")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            TextField("your name", text: $displayName)
                .textInputAutocapitalization(.words)
                .font(.title3)
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.82)))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(.black.opacity(0.08)))
                .padding(.horizontal, 32)
            Button("begin") {
                Task { try? await state.createProfile(displayName: displayName) }
            }
            .buttonStyle(CarteButtonStyle())
            Spacer()
        }
    }
}

@available(iOS 18.0, macOS 15.0, *)
public struct ComposeScreen: View {
    @ObservedObject private var state: CarteAppState
    @State private var showingBack = false
    @State private var recipientNumber = ""
    @State private var selectedContactID: Contact.ID?
    #if canImport(PhotosUI)
    @State private var selectedPhoto: PhotosPickerItem?
    #endif

    public init(state: CarteAppState) {
        self.state = state
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    CardEditor(
                        title: showingBack ? "back" : "front",
                        text: showingBack ? binding(\.backText) : binding(\.frontText),
                        attachmentKind: showingBack ? state.draft.backAttachmentKind : state.draft.frontAttachmentKind,
                        assetID: showingBack ? state.draft.backAttachmentID : state.draft.frontAttachmentID
                    )

                    HStack(spacing: 10) {
                        Button(showingBack ? "front" : "back") { showingBack.toggle() }
                            .buttonStyle(CartePillStyle())
                        #if canImport(PhotosUI)
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label("photo", systemImage: "photo")
                        }
                        .buttonStyle(CartePillStyle())
                        .onChange(of: selectedPhoto) { _, newValue in
                            guard let newValue else { return }
                            Task { await attachPhoto(newValue) }
                        }
                        #endif
                        Button { clearAttachment() } label: {
                            Label("clear media", systemImage: "xmark.circle")
                        }
                        .buttonStyle(CartePillStyle())
                    }

                    if let message = state.statusMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    NumberPad(number: $recipientNumber) {
                        Task { await sendToNumber() }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("or hold a saved number")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ContactGrid(contacts: state.contacts) { contact in
                            Task { await send(to: contact) }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Carte")
            .toolbarTitleDisplayMode(.inline)
        }
    }

    private func binding(_ keyPath: WritableKeyPath<ComposeDraft, String>) -> Binding<String> {
        Binding(
            get: { state.draft[keyPath: keyPath] },
            set: { state.draft[keyPath: keyPath] = $0 }
        )
    }

    #if canImport(PhotosUI)
    private func attachPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            try state.savePhotoAttachment(data: data, to: showingBack ? .back : .front)
            state.setStatusMessage("Photo attached to the \(showingBack ? "back" : "front").")
        } catch {
            state.setStatusMessage(error.localizedDescription)
        }
    }
    #endif

    private func clearAttachment() {
        state.clearAttachment(on: showingBack ? .back : .front)
    }

    private func send(to contact: Contact) async {
        await state.runBusyOperation {
            try await state.sendDraft(to: contact)
        }
    }

    private func sendToNumber() async {
        await state.runBusyOperation {
            guard let number = Int(recipientNumber), number >= 0 else { throw CarteUserFacingError.invalidUserNumber }
            try await state.sendDraft(toUserNumber: number)
            recipientNumber = ""
        }
    }
}

@available(iOS 18.0, macOS 15.0, *)
private struct NumberPad: View {
    @Binding var number: String
    let onSend: () -> Void

    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "⌫", "0", "send"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("send to Carte number")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(number.isEmpty ? "#" : "#\(number)")
                .font(.system(size: 34, weight: .regular, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.72)))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(.black.opacity(0.07)))
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(keys, id: \.self) { key in
                    Button { tap(key) } label: {
                        Text(key)
                            .font(.callout)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                    .buttonStyle(CartePillStyle())
                }
            }
        }
    }

    private func tap(_ key: String) {
        switch key {
        case "send":
            onSend()
        case "⌫":
            if !number.isEmpty { number.removeLast() }
        default:
            guard number.count < 12 else { return }
            number.append(key)
        }
    }
}

@available(iOS 18.0, macOS 15.0, *)
private struct CardEditor: View {
    let title: String
    @Binding var text: String
    let attachmentKind: ComposeDraft.AttachmentKind?
    let assetID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("write something small", text: $text, axis: .vertical)
                .lineLimit(8...14)
                .font(.system(size: 22, weight: .regular, design: .serif))
            if let assetID, attachmentKind == .photo {
                CartePhotoView(assetID: assetID)
                    .frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else if let attachmentKind {
                Label(attachmentKind.rawValue, systemImage: attachmentKind == .photo ? "photo" : "scribble")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.cartePaper))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.black.opacity(0.10)))
        .shadow(color: .black.opacity(0.04), radius: 16, y: 8)
    }
}

@available(iOS 18.0, macOS 15.0, *)
private struct ContactGrid: View {
    let contacts: [Contact]
    let onLongPress: (Contact) -> Void

    private let columns = [GridItem(.adaptive(minimum: 116), spacing: 10)]

    var body: some View {
        if contacts.isEmpty {
            Text("Add a friend from the Me tab by exchanging Carte numbers.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.55)))
        } else {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(contacts) { contact in
                    Text(contact.userNumber.map { "#\($0)  \(contact.displayName)" } ?? contact.displayName)
                        .font(.callout)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.72)))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.black.opacity(0.06)))
                        .onLongPressGesture(minimumDuration: 0.55) { onLongPress(contact) }
                }
            }
        }
    }
}

@available(iOS 18.0, macOS 15.0, *)
public struct InboxScreen: View {
    @ObservedObject private var state: CarteAppState

    public init(state: CarteAppState) { self.state = state }

    public var body: some View {
        NavigationStack {
            CardList(deliveries: state.inbox, emptyText: "your in-tray is empty") { delivery in
                Button("Done") { Task { try? await state.dismissToArchive(delivery) } }
                Button("Erase", role: .destructive) { Task { try? await state.erase(delivery) } }
            }
            .navigationTitle("Tray")
            .toolbar { Button("Refresh") { Task { try? await state.refreshInboxAndArchive() } } }
            .task { try? await state.refreshInboxAndArchive() }
        }
    }
}

@available(iOS 18.0, macOS 15.0, *)
public struct ArchiveScreen: View {
    @ObservedObject private var state: CarteAppState

    public init(state: CarteAppState) { self.state = state }

    public var body: some View {
        NavigationStack {
            CardList(deliveries: state.archive, emptyText: "dismissed cards will be saved here") { delivery in
                Button("Erase", role: .destructive) { Task { try? await state.erase(delivery) } }
            }
            .navigationTitle("Archive")
            .toolbar { Button("Refresh") { Task { try? await state.refreshInboxAndArchive() } } }
        }
    }
}

@available(iOS 18.0, macOS 15.0, *)
private struct CardList<Actions: View>: View {
    let deliveries: [CardDelivery]
    let emptyText: String
    @ViewBuilder let actions: (CardDelivery) -> Actions

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                if deliveries.isEmpty {
                    Text(emptyText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 80)
                } else {
                    ForEach(deliveries) { delivery in
                        DeliveryCard(delivery: delivery, actions: actions)
                    }
                }
            }
            .padding(20)
        }
    }
}

@available(iOS 18.0, macOS 15.0, *)
private struct DeliveryCard<Actions: View>: View {
    let delivery: CardDelivery
    @State private var showingBack = false
    @ViewBuilder let actions: (CardDelivery) -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(delivery.card.senderNumber.map { "from #\($0)  \(delivery.card.senderDisplayName)" } ?? "from \(delivery.card.senderDisplayName)")
                .font(.caption)
                .foregroundStyle(.secondary)
            CardFaceView(card: delivery.card, showingBack: showingBack)
                .onTapGesture { if delivery.card.hasBackSide { showingBack.toggle() } }
            HStack { actions(delivery) }
                .buttonStyle(CartePillStyle())
        }
    }
}

@available(iOS 18.0, macOS 15.0, *)
public struct CardFaceView: View {
    let card: Card
    let showingBack: Bool

    public init(card: Card, showingBack: Bool = false) {
        self.card = card
        self.showingBack = showingBack
    }

    public var body: some View {
        let side = visibleSide
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(side?.index == .back ? "back" : "front")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if card.hasBackSide { Text("tap to examine").font(.caption2).foregroundStyle(.tertiary) }
            }
            content(side?.content)
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.cartePaper))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.black.opacity(0.10)))
    }

    private var visibleSide: CardSide? {
        if showingBack, let back = card.sides.first(where: { $0.index == .back }) { return back }
        return card.sides.first(where: { $0.index == .front })
    }

    @ViewBuilder private func content(_ content: CardSide.Content?) -> some View {
        switch content {
        case .text(let text):
            Text(text)
                .font(.system(size: 22, weight: .regular, design: .serif))
                .foregroundStyle(.primary)
        case .photo(let assetID):
            CartePhotoView(assetID: assetID)
        case .drawing:
            Label("drawing card", systemImage: "scribble")
                .font(.title3)
                .foregroundStyle(.secondary)
        case .none:
            EmptyView()
        }
    }
}

@available(iOS 18.0, macOS 15.0, *)
private struct CartePhotoView: View {
    let assetID: String

    var body: some View {
        #if canImport(UIKit)
        if let image = CarteImageLoader.image(for: assetID) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, alignment: .center)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        } else {
            missingPhoto
        }
        #else
        missingPhoto
        #endif
    }

    private var missingPhoto: some View {
        Label("photo unavailable", systemImage: "photo")
            .font(.title3)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 180)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.42)))
    }
}

@available(iOS 18.0, macOS 15.0, *)
public struct SettingsScreen: View {
    @ObservedObject private var state: CarteAppState
    @State private var contactName = ""
    @State private var userNumber = ""

    public init(state: CarteAppState) { self.state = state }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Carte number") {
                    Text(state.profile?.userNumber.map { "#\($0)" } ?? "iCloud identity pending")
                        .font(.system(.title3, design: .monospaced))
                        .textSelection(.enabled)
                    Text("Exchange this number with a friend. It is assigned once to your iCloud account and is used as your Carte address.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Add contact") {
                    TextField("name", text: $contactName)
                    TextField("number", text: $userNumber)
                        .keyboardType(.numberPad)
                    Button("Add") {
                        Task {
                            await state.runBusyOperation {
                                guard let number = Int(userNumber) else { throw CarteUserFacingError.invalidUserNumber }
                                try await state.addContact(displayName: contactName, userNumber: number)
                                contactName = ""
                                userNumber = ""
                            }
                        }
                    }
                }
                Section("Contacts") {
                    ForEach(state.contacts) { contact in
                        Text(contact.userNumber.map { "#\($0)  \(contact.displayName)" } ?? contact.displayName)
                    }
                    .onDelete { offsets in
                        for index in offsets { Task { try? await state.removeContact(state.contacts[index]) } }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Me")
        }
    }
}

@available(iOS 18.0, macOS 15.0, *)
private struct CarteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(Capsule().fill(.primary.opacity(configuration.isPressed ? 0.72 : 0.92)))
            .foregroundStyle(Color.carteCanvas)
    }
}

@available(iOS 18.0, macOS 15.0, *)
private struct CartePillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(.white.opacity(configuration.isPressed ? 0.55 : 0.78)))
            .overlay(Capsule().stroke(.black.opacity(0.08)))
    }
}

@available(iOS 18.0, macOS 15.0, *)
private extension View {
    func minimalCarteChrome() -> some View {
        background(Color.carteCanvas.ignoresSafeArea())
    }
}

@available(iOS 18.0, macOS 15.0, *)
private extension Color {
    static let carteCanvas = Color(red: 0.965, green: 0.952, blue: 0.924)
    static let cartePaper = Color(red: 1.0, green: 0.992, blue: 0.966)
}
#endif
