import SwiftUI

@main
struct TopoNavApp: App {
    var body: some Scene {
        WindowGroup {
            if MapboxToken.isConfigured {
                ContentView()
            } else {
                MissingTokenView()
            }
        }
    }
}
