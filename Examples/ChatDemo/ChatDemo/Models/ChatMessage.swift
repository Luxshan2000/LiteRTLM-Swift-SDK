import Foundation
import SwiftUI

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: MessageRole
    var text: String
    let image: Data?
    let timestamp = Date()

    enum MessageRole {
        case user
        case model
        case system
    }

    var isUser: Bool { role == .user }
    var isModel: Bool { role == .model }
}
