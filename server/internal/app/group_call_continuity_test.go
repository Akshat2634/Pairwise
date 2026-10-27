package app

import (
	"encoding/json"
	"testing"
	"time"
)

func TestGroupJoinersSurviveOriginalParticipantsLeaving(t *testing.T) {
	for _, test := range []struct {
		name         string
		callerLeaves bool
	}{{"original recipient leaves", false}, {"both original participants leave", true}} {
		t.Run(test.name, func(t *testing.T) {
			s, _ := fixture(t)
			h := s.Handler()
			callerToken := login(t, s)
			target, targetToken := addCallUser(t, s, "original-peer")
			roomID, callID := startAcceptedDirectCall(t, s, callerToken, target, targetToken)
			joinerTokens := []string{}
			for _, name := range []string{"joiner-one", "joiner-two"} {
				_, token := addCallUser(t, s, name)
				joinerTokens = append(joinerTokens, token)
				w := request(h, "POST", "/v1/rooms/"+roomID+"/join-requests", token, "")
				if w.Code != 201 {
					t.Fatalf("create: %d %s", w.Code, w.Body)
				}
				var result struct {
					Request apiJoinRequest `json:"request"`
				}
				if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil {
					t.Fatal(err)
				}
				if w = request(h, "POST", "/v1/join-requests/"+result.Request.ID+"/accept", targetToken, ""); w.Code != 200 {
					t.Fatalf("accept: %d %s", w.Code, w.Body)
				}
				if w = request(h, "POST", "/v1/rooms/"+roomID+"/join", token, ""); w.Code != 200 {
					t.Fatalf("join: %d %s", w.Code, w.Body)
				}
			}
			// Model an established call, past the original acceptance grace period,
			// without waiting in real time or expiring any member heartbeat.
			s.store.lock()
			invite := s.store.s.Calls[callID]
			invite.ExpiresAt = time.Now().Add(-time.Minute)
			s.store.s.Calls[callID] = invite
			// History may age out while the media room is still established.
			// Cleanup must retain accepted admissions until their members leave.
			for id, admission := range s.store.s.JoinRequests {
				admission.UpdatedAt = time.Now().Add(-callHistoryTTL - time.Minute)
				s.store.s.JoinRequests[id] = admission
			}
			s.store.unlock()
			leavingTokens := []string{targetToken}
			remainingTokens := append([]string{}, joinerTokens...)
			if test.callerLeaves {
				leavingTokens = append(leavingTokens, callerToken)
			} else {
				remainingTokens = append(remainingTokens, callerToken)
			}
			for _, token := range leavingTokens {
				w := request(h, "POST", "/v1/rooms/"+roomID+"/leave", token, "")
				if w.Code != 200 {
					t.Fatalf("leave: %d %s", w.Code, w.Body)
				}
			}
			s.store.lock()
			t.Logf("Remaining joined members before invitation poll: %d", len(s.store.s.Rooms[roomID].Members))
			s.store.unlock()
			if w := request(h, "GET", "/v1/join-requests", joinerTokens[0], ""); w.Code != 200 {
				t.Fatalf("history cleanup: %d %s", w.Code, w.Body)
			}
			w := request(h, "GET", "/v1/calls", joinerTokens[0], "")
			if w.Code != 200 {
				t.Fatalf("poll: %d %s", w.Code, w.Body)
			}
			for _, token := range remainingTokens {
				w = request(h, "POST", "/v1/rooms/"+roomID+"/heartbeat", token, "")
				if w.Code != 200 {
					t.Errorf("Remaining participant was removed by pruning: heartbeat=%d %s", w.Code, w.Body)
				}
			}
			// Once only one joined member remains and there are no pending seats,
			// ordinary room cleanup still applies.
			for _, token := range remainingTokens[1:] {
				if w := request(h, "POST", "/v1/rooms/"+roomID+"/leave", token, ""); w.Code != 200 {
					t.Fatalf("final peer leave: %d %s", w.Code, w.Body)
				}
			}
			request(h, "GET", "/v1/calls", remainingTokens[0], "")
			if w := request(h, "POST", "/v1/rooms/"+roomID+"/heartbeat", remainingTokens[0], ""); w.Code != 403 {
				t.Fatalf("lone member should be released: %d %s", w.Code, w.Body)
			}
			request(h, "GET", "/v1/join-requests", remainingTokens[0], "")
			s.store.lock()
			remainingAdmissions := len(s.store.s.JoinRequests)
			s.store.unlock()
			if remainingAdmissions != 0 {
				t.Fatalf("ended admissions should age out: %d remaining", remainingAdmissions)
			}
		})
	}
}
