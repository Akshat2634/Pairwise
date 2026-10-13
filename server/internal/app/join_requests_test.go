package app

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"
	"time"
)

func TestJoinRequestIsVisibleToCallAndAcceptedByAnyMember(t *testing.T) {
	s, _ := fixture(t)
	h := s.Handler()
	callerToken := login(t, s)
	member, memberToken := addCallUser(t, s, "member")
	roomID, _ := startAcceptedDirectCall(t, s, callerToken, member, memberToken)
	requester, requesterToken := addCallUser(t, s, "requester")

	w := request(h, "GET", "/v1/active-calls", requesterToken, "")
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"id":"`+roomID+`"`) {
		t.Fatalf("active call not listed: %d %s", w.Code, w.Body)
	}
	w = request(h, "POST", "/v1/rooms/"+roomID+"/join-requests", requesterToken, "")
	if w.Code != http.StatusCreated {
		t.Fatalf("request to join: %d %s", w.Code, w.Body)
	}
	var created struct {
		Request apiJoinRequest `json:"request"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &created); err != nil {
		t.Fatal(err)
	}
	if created.Request.Requester.ID != requester.ID || created.Request.Room.ID != roomID || created.Request.Status != "pending" {
		t.Fatalf("bad request response: %+v", created.Request)
	}
	w = request(h, "GET", "/v1/join-requests", memberToken, "")
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"id":"`+created.Request.ID+`"`) {
		t.Fatalf("participant did not see join request: %d %s", w.Code, w.Body)
	}
	w = request(h, "POST", "/v1/join-requests/"+created.Request.ID+"/accept", callerToken, "")
	if w.Code != http.StatusOK {
		t.Fatalf("participant accept: %d %s", w.Code, w.Body)
	}
	w = request(h, "POST", "/v1/rooms/"+roomID+"/join", requesterToken, "")
	if w.Code != http.StatusOK {
		t.Fatalf("requester join accepted call: %d %s", w.Code, w.Body)
	}

	// A participant can grant the pending request, but an unrelated teammate
	// cannot accept it or join the resulting private room.
	_, outsiderToken := addCallUser(t, s, "outsider")
	w = request(h, "POST", "/v1/join-requests/"+created.Request.ID+"/accept", outsiderToken, "")
	if w.Code != http.StatusConflict {
		t.Fatalf("accepted request should no longer be actionable: %d %s", w.Code, w.Body)
	}
	if w = request(h, "POST", "/v1/rooms/"+roomID+"/join", outsiderToken, ""); w.Code != 403 {
		t.Fatalf("outsider joined private call: %d %s", w.Code, w.Body)
	}
}

func TestJoinRequestAcceptRequiresCallParticipantAndDuplicateIsIdempotent(t *testing.T) {
	s, _ := fixture(t)
	h := s.Handler()
	callerToken := login(t, s)
	member, memberToken := addCallUser(t, s, "member")
	roomID, _ := startAcceptedDirectCall(t, s, callerToken, member, memberToken)
	_, requesterToken := addCallUser(t, s, "requester")
	_, outsiderToken := addCallUser(t, s, "outsider")

	w := request(h, "POST", "/v1/rooms/"+roomID+"/join-requests", requesterToken, "")
	var created struct {
		Request apiJoinRequest `json:"request"`
	}
	_ = json.Unmarshal(w.Body.Bytes(), &created)
	second := request(h, "POST", "/v1/rooms/"+roomID+"/join-requests", requesterToken, "")
	var duplicate struct {
		Request apiJoinRequest `json:"request"`
	}
	_ = json.Unmarshal(second.Body.Bytes(), &duplicate)
	if second.Code != http.StatusOK || duplicate.Request.ID != created.Request.ID {
		t.Fatalf("duplicate request was not idempotent: %d %s", second.Code, second.Body)
	}
	w = request(h, "POST", "/v1/join-requests/"+created.Request.ID+"/accept", outsiderToken, "")
	if w.Code != http.StatusForbidden {
		t.Fatalf("non-member accepted request: %d %s", w.Code, w.Body)
	}
	w = request(h, "POST", "/v1/join-requests/"+created.Request.ID+"/decline", memberToken, "")
	if w.Code != http.StatusOK {
		t.Fatalf("decline request: %d %s", w.Code, w.Body)
	}
	w = request(h, "POST", "/v1/rooms/"+roomID+"/join", requesterToken, "")
	if w.Code != http.StatusForbidden {
		t.Fatalf("declined requester joined: %d %s", w.Code, w.Body)
	}
}

func TestJoinRequestsReserveSeatsAndCannotOverfillRoom(t *testing.T) {
	s, _ := fixture(t)
	h := s.Handler()
	callerToken := login(t, s)
	member, memberToken := addCallUser(t, s, "member")
	roomID, _ := startAcceptedDirectCall(t, s, callerToken, member, memberToken)
	_, firstToken := addCallUser(t, s, "first")
	_, secondToken := addCallUser(t, s, "second")
	_, thirdToken := addCallUser(t, s, "third")

	first := request(h, "POST", "/v1/rooms/"+roomID+"/join-requests", firstToken, "")
	if first.Code != http.StatusCreated {
		t.Fatalf("first join request: %d %s", first.Code, first.Body)
	}
	var firstBody struct {
		Request apiJoinRequest `json:"request"`
	}
	if err := json.Unmarshal(first.Body.Bytes(), &firstBody); err != nil {
		t.Fatal(err)
	}

	second := request(h, "POST", "/v1/rooms/"+roomID+"/join-requests", secondToken, "")
	if second.Code != http.StatusCreated {
		t.Fatalf("second join request should reserve the last seat: %d %s", second.Code, second.Body)
	}
	var secondBody struct {
		Request apiJoinRequest `json:"request"`
	}
	if err := json.Unmarshal(second.Body.Bytes(), &secondBody); err != nil {
		t.Fatal(err)
	}

	third := request(h, "POST", "/v1/rooms/"+roomID+"/join-requests", thirdToken, "")
	if third.Code != http.StatusConflict {
		t.Fatalf("room should reject a request after all seats are reserved: %d %s", third.Code, third.Body)
	}

	for _, id := range []string{firstBody.Request.ID, secondBody.Request.ID} {
		accepted := request(h, "POST", "/v1/join-requests/"+id+"/accept", callerToken, "")
		if accepted.Code != http.StatusOK {
			t.Fatalf("accept reserved seat %s: %d %s", id, accepted.Code, accepted.Body)
		}
	}

	if got := roomSeatCountLocked(s.store.s, roomID, time.Now().UTC()); got != maxRoom {
		t.Fatalf("room seat count = %d, want %d", got, maxRoom)
	}
}
