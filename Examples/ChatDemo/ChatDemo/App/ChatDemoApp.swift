import SwiftUI

@main
struct ChatDemoApp: App {
    @State private var chatVM = ChatViewModel()

    var body: some Scene {
        WindowGroup {
            ChatView()
                .environment(chatVM)
                .background(Color(.systemBackground).ignoresSafeArea())
        }
    }
}
