import Foundation
import Testing
@testable import PairDesk

struct CallHistoryTests {
    private func invitation(createdAt: String? = nil, startedAt: String? = nil,
                            endedAt: String? = nil, status: String = "cancelled") throws -> CallInvitation {
        let user = ["id": "user", "name": "Test person", "email": "test@example.invalid"]
        var call: [String: Any] = ["id": "call", "status": status, "caller": user, "target": user,
                                  "room": ["id": "room", "name": "Direct call", "participantCount": 0, "participants": []],
                                  "expiresAt": "2026-10-29T10:00:45Z"]
        call["createdAt"] = createdAt
        call["startedAt"] = startedAt
        call["endedAt"] = endedAt
        return try JSONDecoder().decode(CallInvitation.self, from: JSONSerialization.data(withJSONObject: call))
    }

    @Test(arguments: ["2026-10-29T10:00:00Z", "2026-10-29T10:00:00.123456789Z", "2026-10-29T15:30:00+05:30"])
    func realServerTimestampsNeverBecomeYearOne(_ timestamp: String) throws {
        let call = try invitation(createdAt: timestamp)
        let parsed = try #require(call.createdDate as Date?)
        #expect(Calendar(identifier: .gregorian).component(.year, from: parsed) == 2026)
    }

    @Test(arguments: [nil, "", "not-a-date"] as [String?])
    func missingOrInvalidDatesHaveNoPlaceholder(_ timestamp: String?) throws {
        let call = try invitation(createdAt: timestamp)
        #expect((call.createdDate as Date?) == nil)
        #expect(call.historyDateText == nil)
        #expect(call.historyDurationText == "Duration unavailable")
    }

    @Test(arguments: [("2026-10-29T10:03:10.123456789Z", "Duration 3:05"),
                      ("2026-10-29T11:02:08.123456789Z", "Duration 1:02:03"),
                      ("2026-10-29T10:00:05.123456789Z", "Duration 0:00")])
    func durationUsesAnswerToEndAndDoesNotIncludeRinging(_ end: String, _ expected: String) throws {
        let call = try invitation(createdAt: "2026-10-29T09:59:30Z",
                                  startedAt: "2026-10-29T10:00:05.123456789Z", endedAt: end)
        #expect(call.historyDurationText == expected)
        #expect(call.historyStatusLabel(incoming: true) == "Call ended")
        #expect(call.historyDateText?.hasPrefix("Ended ") == true)
    }

    @Test(arguments: ["not-a-date", "2026-10-29T09:59:59Z"])
    func invalidAndReversedDurationsAreUnavailable(_ end: String) throws {
        let call = try invitation(startedAt: "2026-10-29T10:00:00Z", endedAt: end)
        #expect(call.historyDurationText == "Duration unavailable")
    }

    @Test(arguments: ["expired", "declined", "cancelled"])
    func unansweredCallsNeverShowTalkDuration(_ status: String) throws {
        let call = try invitation(createdAt: "2026-10-29T10:00:00Z", endedAt: "2026-10-29T10:00:45Z", status: status)
        #expect(call.historyDurationText == nil)
        #expect(call.historyStatusLabel(incoming: true) == (status == "expired" ? "Missed call" : status == "declined" ? "Declined" : "Cancelled"))
    }

    @Test func olderRecordsKeepTheirDateWithoutInventingDuration() throws {
        let call = try invitation(createdAt: "2026-10-29T10:00:00.123456789Z")
        #expect(call.historyDurationText == "Duration unavailable")
        #expect(call.historyDateText?.hasPrefix("Called ") == true)
    }
}
