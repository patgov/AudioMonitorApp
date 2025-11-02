
import SwiftUI


@main
struct AudioMonitorApp: App {
    private var appWrapper = AudioMonitorAppWrapper()
    
    var body: some Scene {
        WindowGroup {
            appWrapper
        }
    }
}
