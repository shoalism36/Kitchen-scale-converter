import SwiftUI

@main
struct ProduceOrderGuideApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store)
        }
    }
}
