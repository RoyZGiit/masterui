import SwiftUI

/// Sheet for creating a new CLI session and adding it to an existing group chat.
/// Reuses NewCLISessionSheet for full CLI target selection.
struct NewGroupParticipantSessionSheet: View {
    @ObservedObject var groupManager: GroupChatManager
    @ObservedObject var groupChat: GroupChatSession
    @ObservedObject var sessionManager: CLISessionManager
    @Binding var isPresented: Bool
    var onCreated: ((UUID) -> Void)? = nil

    var body: some View {
        NewCLISessionSheet(sessionManager: sessionManager) { createdSession in
            _ = groupManager.addParticipantSession(groupChatID: groupChat.id, sessionID: createdSession.id)
            onCreated?(createdSession.id)
        }
    }
}
