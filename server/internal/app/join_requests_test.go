package app

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"
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
