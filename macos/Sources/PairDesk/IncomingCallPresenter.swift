import Combine
import Foundation

enum IncomingCallPrompt: Identifiable {
    case invitation(CallInvitation)
    case joinRequest(CallJoinRequest)

    var id: String {
        switch self {
        case .invitation(let call): return "call-\(call.id)"
        case .joinRequest(let request): return "join-\(request.id)"
        }
    }

    var person: TeamUser {
        switch self {
        case .invitation(let call): return call.caller
        case .joinRequest(let request): return request.requester
        }
    }

    var isJoinRequest: Bool {
        if case .joinRequest = self { return true }
        return false
    }
}

/// Keeps call prompts independent of the menu bar popover. Observe all inputs:
/// invitations can arrive before sign-in finishes, and leaving a room invalidates
/// its join requests even before the next server poll.
@MainActor
final class IncomingCallPresenter {
    private let store: AppStore
    private let windows: AppWindows
    private var subscriptions = Set<AnyCancellable>()
    private(set) var shownPromptID: String?

    init(store: AppStore, windows: AppWindows? = nil) {
        self.store = store
        self.windows = windows ?? .shared
        Publishers.Merge4(store.$callInvitations.map { _ in () }, store.$joinRequests.map { _ in () },
                          store.$activeRoom.map { _ in () }, store.$user.map { _ in () })
            .sink { [weak self] in
                // @Published sends before storage changes. Read the settled state.
                Task { @MainActor [weak self] in self?.sync() }
            }.store(in: &subscriptions)
        sync()
    }

    private func sync() {
        let id = store.incomingCallPrompts.first?.id
        guard id != shownPromptID || (id != nil && !windows.isShown("incoming")) else { return }
        shownPromptID = id
        if id != nil { windows.showIncomingCall(store: store) }
        else { windows.close("incoming") }
    }
}
