package app

import (
	"encoding/json"
	"fmt"
	"net/http"
	"testing"
	"time"
)

func listedGroupCall(t *testing.T, s *Server, token, id string) *apiCall {
	t.Helper()
	w := request(s.Handler(), "GET", "/v1/calls", token, "")
	if w.Code != http.StatusOK {
		t.Fatalf("list calls: %d %s", w.Code, w.Body)
	}
	var response struct {
		Calls []apiCall `json:"calls"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
		t.Fatal(err)
	}
	for _, call := range response.Calls {
		if call.ID == id {
			return &call
		}
	}
	return nil
}

func TestCurrentRoomMembersSeeInvitesWithoutReceivingPrivateHistoryOrActions(t *testing.T) {
	s, _ := fixture(t)
	h := s.Handler()
	aToken := login(t, s)
	b, bToken := addCallUser(t, s, "member-b")
	c, cToken := addCallUser(t, s, "invitee-c")
	d, dToken := addCallUser(t, s, "outsider-d")
	roomID, _ := startAcceptedDirectCall(t, s, aToken, b, bToken)
	invite := func(target User) string {
		t.Helper()
		w := request(h, "POST", "/v1/calls", aToken, fmt.Sprintf(`{"userId":%q,"roomId":%q}`, target.ID, roomID))
		if w.Code != http.StatusCreated {
			t.Fatalf("invite: %d %s", w.Code, w.Body)
		}
		var response struct {
			Call apiCall `json:"call"`
		}
		if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
			t.Fatal(err)
		}
		return response.Call.ID
	}
	id := invite(c)
	if call := listedGroupCall(t, s, bToken, id); call == nil || call.Status != callPending || call.Target.ID != c.ID {
		t.Fatalf("B cannot see A's pending invitation to C: %+v", call)
	}
	if listedGroupCall(t, s, dToken, id) != nil {
		t.Fatal("outsider can see a private invitation")
	}
	for _, action := range []string{"accept", "decline", "cancel"} {
		if w := request(h, "POST", "/v1/calls/"+id+"/"+action, bToken, ""); w.Code != http.StatusForbidden {
			t.Fatalf("B can %s another member's invitation: %d %s", action, w.Code, w.Body)
		}
	}
	s.store.lock()
	rm := s.store.s.Rooms[roomID]
	rm.Members[b.ID] = Member{UserID: b.ID, LastSeen: time.Now().Add(-2 * reservationTTL)}
	s.store.s.Rooms[roomID] = rm
	s.store.unlock()
	if listedGroupCall(t, s, bToken, id) != nil {
		t.Fatal("stale room member can still see the invitation")
	}
	s.store.lock()
	rm.Members[b.ID] = Member{UserID: b.ID, LastSeen: time.Now().UTC()}
	s.store.s.Rooms[roomID] = rm
	s.store.unlock()
	if w := request(h, "POST", "/v1/calls/"+id+"/decline", cToken, ""); w.Code != http.StatusOK {
		t.Fatalf("decline: %d %s", w.Code, w.Body)
	}
	if listedGroupCall(t, s, bToken, id) != nil {
		t.Fatal("another member's private call history was exposed")
	}
	if call := listedGroupCall(t, s, aToken, id); call == nil || call.Status != callDeclined {
		t.Fatal("caller's history disappeared")
	}
	id = invite(c)
	if w := request(h, "POST", "/v1/calls/"+id+"/accept", cToken, ""); w.Code != http.StatusOK {
		t.Fatalf("accept: %d %s", w.Code, w.Body)
	}
	if call := listedGroupCall(t, s, bToken, id); call == nil || call.Status != callAccepted {
		t.Fatal("B cannot see C joining")
	}
	dID := invite(d)
	if w := request(h, "POST", "/v1/rooms/"+roomID+"/leave", bToken, ""); w.Code != http.StatusOK {
		t.Fatalf("leave: %d %s", w.Code, w.Body)
	}
	if listedGroupCall(t, s, bToken, id) != nil || listedGroupCall(t, s, bToken, dID) != nil {
		t.Fatal("departed member can still see current room invitations")
	}
	if call := listedGroupCall(t, s, aToken, dID); call == nil || call.Status != callPending {
		t.Fatal("leaving member incorrectly ended the remaining group's invitation")
	}
}
