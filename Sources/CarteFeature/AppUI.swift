#if canImport(SwiftUI) && canImport(Combine) && os(iOS)
import CarteCore
import SwiftUI
#if canImport(PhotosUI)
import PhotosUI
#endif

@available(iOS 18.0, *)
public struct CarteRootView: View {
    @ObservedObject private var state: CarteAppState

    public init(state: CarteAppState) {
        self.state = state
    }

    public var body: some View {
        ZStack {
            CarteTheme.canvas.ignoresSafeArea()
            if state.profile == nil {
                OnboardingView(state: state)
            } else {
                MainTabs(state: state)
            }
        }
        .overlay(alignment: .top) {
            if let message = state.statusMessage {
                StatusBanner(message: message) { state.setStatusMessage(nil) }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: state.statusMessage)
        .task { await state.bootstrap() }
    }
}

@available(iOS 18.0, *)
private struct MainTabs: View {
    @ObservedObject var state: CarteAppState

    var body: some View {
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
    }
}

@available(iOS 18.0, *)
private struct OnboardingView: View {
    @ObservedObject var state: CarteAppState
    @State private var displayName = ""

    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            VStack(spacing: 12) {
                Text("Carte")
                    .font(.system(size: 62, weight: .regular, design: .serif))
                    .tracking(-3)
                Text("postcards, not posts")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 12) {
                TextField("your name", text: $displayName)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .font(.title3)
                    .padding(18)
                    .background(CarteTheme.card, in: RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(.black.opacity(0.08)))
                Button {
                    Task { await state.runBusyOperation { try await state.createProfile(displayName: displayName) } }
                } label: {
                    Label("Create iCloud Carte", systemImage: "icloud")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CartePrimaryButtonStyle())
                Text("Carte uses iCloud and CloudKit for delivery, then saves cards locally on your phone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            Spacer()
        }
        .padding(24)
    }
}

@available(iOS 18.0, *)
public struct ComposeScreen: View {
    @ObservedObject private var state: CarteAppState
    @State private var side: CardSide.Index = .front
    @State private var recipientNumber = ""
    #if canImport(PhotosUI)
    @State private var selectedPhoto: PhotosPickerItem?
    #endif

    public init(state: CarteAppState) {
        self.state = state
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    HeaderBlock(
                        eyebrow: state.currentUserNumber.map { "your number #\($0)" } ?? "iCloud number pending",
                        title: "Write a card",
                        subtitle: "Choose a side, write a note, add a photo if you want, then send by Carte number."
                    )

                    SideToggle(side: $side)

                    PostcardComposer(
                        side: side,
                        text: side == .front ? binding(\.frontText) : binding(\.backText),
                        attachmentKind: attachmentKind,
                        assetID: attachmentID
                    )

                    HStack(spacing: 10) {
                        #if canImport(PhotosUI)
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label("Choose photo", systemImage: "photo.on.rectangle")
                        }
                        .buttonStyle(CartePillStyle())
                        #endif
                        if attachmentID != nil {
                            Button(role: .destructive) { state.clearAttachment(on: side) } label: {
                                Label("Remove photo", systemImage: "xmark.circle")
                            }
                            .buttonStyle(CartePillStyle())
                        }
                        Spacer(minLength: 0)
                    }
                    #if canImport(PhotosUI)
                    .onChange(of: selectedPhoto) { _, newValue in
                        guard let newValue else { return }
                        Task { await attachPhoto(newValue) }
                    }
                    #endif

                    SendPanel(number: $recipientNumber, contacts: state.contacts) { number in
                        Task { await send(to: number) }
                    } onContact: { contact in
                        Task { await send(to: contact) }
                    }
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(CarteTheme.canvas)
            .navigationTitle("Write")
            .toolbarTitleDisplayMode(.inline)
        }
    }

    private var attachmentID: String? {
        side == .front ? state.draft.frontAttachmentID : state.draft.backAttachmentID
    }

    private var attachmentKind: ComposeDraft.AttachmentKind? {
        side == .front ? state.draft.frontAttachmentKind : state.draft.backAttachmentKind
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
            try state.savePhotoAttachment(data: data, to: side)
            selectedPhoto = nil
            state.setStatusMessage("Photo added to the \(side.label).")
        } catch {
            state.setStatusMessage(error.localizedDescription)
        }
    }
    #endif

    private func send(to number: Int) async {
        await state.runBusyOperation {
            try await state.sendDraft(toUserNumber: number)
            recipientNumber = ""
        }
    }

    private func send(to contact: Contact) async {
        await state.runBusyOperation {
            try await state.sendDraft(to: contact)
        }
    }
}

@available(iOS 18.0, *)
private struct SideToggle: View {
    @Binding var side: CardSide.Index

    var body: some View {
        HStack(spacing: 8) {
            ForEach(CardSide.Index.allCases, id: \.self) { option in
                Button {
                    side = option
                } label: {
                    Text(option.label)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CarteSegmentButtonStyle(isSelected: side == option))
            }
        }
        .padding(5)
        .background(.white.opacity(0.45), in: Capsule())
    }
}

@available(iOS 18.0, *)
private struct PostcardComposer: View {
    let side: CardSide.Index
    @Binding var text: String
    let attachmentKind: ComposeDraft.AttachmentKind?
    let assetID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(side.label.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "postcard")
                    .foregroundStyle(.tertiary)
            }

            TextField(side == .front ? "write the front…" : "write the back…", text: $text, axis: .vertical)
                .lineLimit(7...14)
                .font(.system(size: 24, weight: .regular, design: .serif))
                .foregroundStyle(.primary)
                .padding(.vertical, 4)

            if let assetID, attachmentKind == .photo {
                CartePhotoView(assetID: assetID)
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
        .background(CarteTheme.paper, in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(.black.opacity(0.10)))
        .shadow(color: .black.opacity(0.06), radius: 24, y: 12)
        .accessibilityElement(children: .contain)
    }
}

@available(iOS 18.0, *)
private struct SendPanel: View {
    @Binding var number: String
    let contacts: [Contact]
    let onNumber: (Int) -> Void
    let onContact: (Contact) -> Void

    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "⌫", "0", "send"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 9), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Address")
                .font(.headline)
            Text(number.isEmpty ? "#" : "#\(number)")
                .font(.system(size: 38, weight: .regular, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(CarteTheme.card, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(.black.opacity(0.07)))

            LazyVGrid(columns: columns, spacing: 9) {
                ForEach(keys, id: \.self) { key in
                    Button { tap(key) } label: {
                        Text(key)
                            .font(.callout.weight(key == "send" ? .semibold : .regular))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                    .buttonStyle(CarteKeyButtonStyle(isSend: key == "send"))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Saved numbers")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ContactGrid(contacts: contacts, onLongPress: onContact)
            }
        }
        .padding(18)
        .background(.white.opacity(0.38), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.black.opacity(0.06)))
    }

    private func tap(_ key: String) {
        switch key {
        case "send":
            guard let value = Int(number), value >= 0 else { return }
            onNumber(value)
        case "⌫":
            if !number.isEmpty { number.removeLast() }
        default:
            guard number.count < 12 else { return }
            number.append(key)
        }
    }
}

@available(iOS 18.0, *)
private struct ContactGrid: View {
    let contacts: [Contact]
    let onLongPress: (Contact) -> Void
    private let columns = [GridItem(.adaptive(minimum: 138), spacing: 10)]

    var body: some View {
        if contacts.isEmpty {
            EmptyInline(text: "Add friends in Me by exchanging Carte numbers.")
        } else {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(contacts) { contact in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(contact.displayName)
                            .font(.callout.weight(.medium))
                        Text(contact.userNumber.map { "#\($0)" } ?? "number pending")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(CarteTheme.card, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(.black.opacity(0.06)))
                    .onLongPressGesture(minimumDuration: 0.45) { onLongPress(contact) }
                    .accessibilityHint("Press and hold to send this card")
                }
            }
        }
    }
}

@available(iOS 18.0, *)
public struct InboxScreen: View {
    @ObservedObject private var state: CarteAppState
    @State private var selectedDelivery: CardDelivery?

    public init(state: CarteAppState) { self.state = state }

    public var body: some View {
        NavigationStack {
            DeliveryCollection(
                deliveries: state.inbox,
                emptyTitle: "Your in-tray is empty",
                emptyBody: "Cards appear here only while they are in transit. Tap Done after reading to save a local PDF."
            ) { delivery in
                selectedDelivery = delivery
            }
            .navigationTitle("Tray")
            .toolbar { Button("Refresh") { Task { await state.runBusyOperation { try await state.refreshInboxAndArchive() } } } }
            .task { try? await state.refreshInboxAndArchive() }
            .sheet(item: $selectedDelivery) { delivery in
                CardReader(delivery: delivery, mode: .inbox) {
                    await state.runBusyOperation { try await state.dismissToArchive(delivery) }
                    selectedDelivery = nil
                } onErase: {
                    await state.runBusyOperation { try await state.erase(delivery) }
                    selectedDelivery = nil
                }
            }
        }
    }
}

@available(iOS 18.0, *)
public struct ArchiveScreen: View {
    @ObservedObject private var state: CarteAppState
    @State private var selectedDelivery: CardDelivery?

    public init(state: CarteAppState) { self.state = state }

    public var body: some View {
        NavigationStack {
            DeliveryCollection(
                deliveries: state.archive,
                emptyTitle: "Archive is empty",
                emptyBody: "Dismissed cards are stored locally and exported as PDFs in Documents/Carte Postcards."
            ) { delivery in
                selectedDelivery = delivery
            }
            .navigationTitle("Archive")
            .toolbar { Button("Refresh") { Task { await state.runBusyOperation { try await state.refreshInboxAndArchive() } } } }
            .sheet(item: $selectedDelivery) { delivery in
                CardReader(delivery: delivery, mode: .archive, onDone: nil) {
                    await state.runBusyOperation { try await state.erase(delivery) }
                    selectedDelivery = nil
                }
            }
        }
    }
}

@available(iOS 18.0, *)
private struct DeliveryCollection: View {
    let deliveries: [CardDelivery]
    let emptyTitle: String
    let emptyBody: String
    let onSelect: (CardDelivery) -> Void

    private let columns = [GridItem(.adaptive(minimum: 280), spacing: 16)]

    var body: some View {
        ScrollView {
            if deliveries.isEmpty {
                EmptyState(title: emptyTitle, body: emptyBody)
                    .padding(.top, 80)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(deliveries) { delivery in
                        DeliveryPreview(delivery: delivery)
                            .onTapGesture { onSelect(delivery) }
                    }
                }
                .padding(20)
            }
        }
        .background(CarteTheme.canvas)
    }
}

@available(iOS 18.0, *)
private struct DeliveryPreview: View {
    let delivery: CardDelivery

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(delivery.card.senderNumber.map { "#\($0)" } ?? "—")
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.72), in: Capsule())
                Spacer()
                Text(delivery.deliveredAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            CardFaceView(card: delivery.card, showingBack: false)
                .frame(minHeight: 220)
            Text("from \(delivery.card.senderDisplayName)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

@available(iOS 18.0, *)
private struct CardReader: View {
    enum Mode { case inbox, archive }

    let delivery: CardDelivery
    let mode: Mode
    let onDone: (() async -> Void)?
    let onErase: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showingBack = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text(delivery.card.senderNumber.map { "from #\($0)  \(delivery.card.senderDisplayName)" } ?? "from \(delivery.card.senderDisplayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                CardFaceView(card: delivery.card, showingBack: showingBack)
                    .onTapGesture { if delivery.card.hasBackSide { showingBack.toggle() } }
                    .padding(.horizontal, 18)
                if delivery.card.hasBackSide {
                    Button(showingBack ? "Show front" : "Show back") { showingBack.toggle() }
                        .buttonStyle(CartePillStyle())
                }
                Spacer()
                HStack(spacing: 12) {
                    if let onDone {
                        Button {
                            Task { await onDone(); dismiss() }
                        } label: {
                            Label("Done", systemImage: "checkmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(CartePrimaryButtonStyle())
                    }
                    Button(role: .destructive) {
                        Task { await onErase(); dismiss() }
                    } label: {
                        Label("Erase", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CarteDestructiveButtonStyle())
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
            }
            .padding(.top, 20)
            .background(CarteTheme.canvas)
            .navigationTitle(mode == .inbox ? "In-tray" : "Archive")
            .toolbarTitleDisplayMode(.inline)
        }
    }
}

@available(iOS 18.0, *)
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
                Text((side?.index ?? .front).label.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if card.hasBackSide { Image(systemName: "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(.tertiary) }
            }
            content(side?.content)
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
        .background(CarteTheme.paper, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.black.opacity(0.10)))
        .shadow(color: .black.opacity(0.04), radius: 18, y: 8)
    }

    private var visibleSide: CardSide? {
        if showingBack, let back = card.sides.first(where: { $0.index == .back }) { return back }
        return card.sides.first(where: { $0.index == .front })
    }

    @ViewBuilder private func content(_ content: CardSide.Content?) -> some View {
        switch content {
        case .text(let text):
            Text(text.isEmpty ? " " : text)
                .font(.system(size: 23, weight: .regular, design: .serif))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
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

@available(iOS 18.0, *)
private struct CartePhotoView: View {
    let assetID: String

    var body: some View {
        #if canImport(UIKit)
        if let image = CarteImageLoader.image(for: assetID) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, alignment: .center)
                .clipShape(RoundedRectangle(cornerRadius: 16))
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
            .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.42)))
    }
}

@available(iOS 18.0, *)
public struct SettingsScreen: View {
    @ObservedObject private var state: CarteAppState
    @State private var contactName = ""
    @State private var userNumber = ""

    public init(state: CarteAppState) { self.state = state }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Your Carte") {
                    HStack {
                        Text(state.profile?.displayName ?? "Carte User")
                        Spacer()
                        Text(state.profile?.userNumber.map { "#\($0)" } ?? "iCloud pending")
                            .font(.system(.title3, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    Text("Give your Carte number to people you want to receive cards from. Delivery uses CloudKit; archived cards remain on this iPhone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Add contact") {
                    TextField("name", text: $contactName)
                    TextField("Carte number", text: $userNumber)
                        .keyboardType(.numberPad)
                    Button("Add contact") {
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
                    if state.contacts.isEmpty {
                        Text("No saved numbers yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(state.contacts) { contact in
                            HStack {
                                Text(contact.displayName)
                                Spacer()
                                Text(contact.userNumber.map { "#\($0)" } ?? "—")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { Task { try? await state.removeContact(state.contacts[index]) } }
                        }
                    }
                }

                Section("Local PDF archive") {
                    Text(state.localPDFArchiveDirectory()?.path(percentEncoded: false) ?? "Documents/Carte Postcards")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Text("In Files, look under On My iPhone → Carte → Carte Postcards after opening a received card and tapping Done.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(CarteTheme.canvas)
            .navigationTitle("Me")
        }
    }
}

@available(iOS 18.0, *)
private struct HeaderBlock: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 42, weight: .regular, design: .serif))
                .tracking(-2)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@available(iOS 18.0, *)
private struct EmptyState: View {
    let title: String
    let body: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "postcard")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.title2.weight(.medium))
            Text(body)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

@available(iOS 18.0, *)
private struct EmptyInline: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CarteTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }
}

@available(iOS 18.0, *)
private struct StatusBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        Button(action: dismiss) {
            HStack(spacing: 10) {
                Image(systemName: "info.circle")
                Text(message)
                    .font(.footnote)
                    .lineLimit(2)
                Spacer()
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.black.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}

@available(iOS 18.0, *)
private struct CartePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .background(Capsule().fill(.primary.opacity(configuration.isPressed ? 0.72 : 0.94)))
            .foregroundStyle(CarteTheme.canvas)
    }
}

@available(iOS 18.0, *)
private struct CarteDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .background(Capsule().fill(Color.red.opacity(configuration.isPressed ? 0.12 : 0.08)))
            .foregroundStyle(.red)
            .overlay(Capsule().stroke(Color.red.opacity(0.22)))
    }
}

@available(iOS 18.0, *)
private struct CartePillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.medium))
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(Capsule().fill(.white.opacity(configuration.isPressed ? 0.50 : 0.78)))
            .overlay(Capsule().stroke(.black.opacity(0.08)))
    }
}

@available(iOS 18.0, *)
private struct CarteSegmentButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .padding(.vertical, 11)
            .background(Capsule().fill(isSelected ? .primary.opacity(configuration.isPressed ? 0.75 : 0.92) : .clear))
            .foregroundStyle(isSelected ? CarteTheme.canvas : .primary)
    }
}

@available(iOS 18.0, *)
private struct CarteKeyButtonStyle: ButtonStyle {
    let isSend: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 16).fill(isSend ? .primary.opacity(configuration.isPressed ? 0.72 : 0.92) : .white.opacity(configuration.isPressed ? 0.5 : 0.75)))
            .foregroundStyle(isSend ? CarteTheme.canvas : .primary)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.black.opacity(isSend ? 0 : 0.07)))
    }
}

@available(iOS 18.0, *)
private enum CarteTheme {
    static let canvas = Color(red: 0.965, green: 0.952, blue: 0.924)
    static let paper = Color(red: 1.0, green: 0.992, blue: 0.966)
    static let card = Color.white.opacity(0.72)
}

private extension CardSide.Index {
    var label: String {
        switch self {
        case .front: return "front"
        case .back: return "back"
        }
    }
}
#endif
