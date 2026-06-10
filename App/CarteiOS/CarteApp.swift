import SwiftUI
import CarteFeature

@main
struct CarteiOSApp: App {
    @StateObject private var state = CarteAppState(
        transport: CloudKitCardTransport(),
        store: JSONProfileStore(),
        identityDirectory: CloudKitIdentityDirectory()
    )

    var body: some Scene {
        WindowGroup {
            CarteRootView(state: state)
                .task { await state.bootstrap() }
        }
    }
}
