import Foundation

struct TeamUser: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let email: String
    var online: Bool?
    var busy: Bool?
    var admin: Bool?
    var enabled: Bool?
    var initials: String { name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased() }
}

struct PairRoom: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    var participantCount: Int
    var participants: [TeamUser]
}

struct LoginResponse: Decodable { let token: String; let user: TeamUser; let expiresAt: String }
struct MeResponse: Decodable { let user: TeamUser }
struct UsersResponse: Decodable { let users: [TeamUser] }
struct RoomsResponse: Decodable { let rooms: [PairRoom] }
struct RoomResponse: Decodable { let room: PairRoom }
struct JoinResponse: Decodable { let room: PairRoom; let url: String; let token: String; let participantIdentity: String }
struct ErrorResponse: Decodable { let error: String }
struct EmptyBody: Encodable {}

struct APIError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}

struct CallInvitation: Decodable, Identifiable, Equatable {
    let id: String
    let status: String
    let caller: TeamUser
    let target: TeamUser
    let room: PairRoom
    let expiresAt: String
}
struct CallResponse: Decodable { let call: CallInvitation }
struct CallsResponse: Decodable { let calls: [CallInvitation] }
