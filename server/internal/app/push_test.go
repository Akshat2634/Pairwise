package app

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

type fakePushSender struct {
	sent chan struct {
		device  DeviceRegistration
		event   string
		callID  string
		expires time.Time
	}
}

func (f *fakePushSender) Send(_ context.Context, d DeviceRegistration, event, callID string, expires time.Time) error {
	f.sent <- struct {
		device  DeviceRegistration
		event   string
		callID  string
		expires time.Time
	}{d, event, callID, expires}
	return nil
}

func TestDeviceRegistrationRequiresAuthValidPlatformAndHidesTokens(t *testing.T) {
	s, _ := fixture(t)
	h := s.Handler()
	token := login(t, s)
	if w := request(h, "POST", "/v1/devices", "", `{"deviceId":"phone","platform":"android","pushToken":"secret"}`); w.Code != http.StatusUnauthorized {
		t.Fatalf("unauthenticated register: %d", w.Code)
	}
	if w := request(h, "POST", "/v1/devices", token, `{"deviceId":"phone","platform":"android","pushToken":"secret","voipToken":"extra"}`); w.Code != http.StatusBadRequest {
		t.Fatalf("mixed token kinds accepted: %d", w.Code)
	}
	w := request(h, "POST", "/v1/devices", token, `{"deviceId":"phone","platform":"android","pushToken":"secret"}`)
	if w.Code != http.StatusOK || strings.Contains(w.Body.String(), "secret") {
		t.Fatalf("registration leaked token or failed: %d %s", w.Code, w.Body)
	}
	s.store.lock()
	var d DeviceRegistration
	count := len(s.store.s.Devices)
	for _, registered := range s.store.s.Devices {
		d = registered
	}
	s.store.unlock()
	if d.UserID == "" || d.PushToken != "secret" {
		t.Fatalf("device not stored for authenticated owner: count=%d device=%+v", count, d)
	}
	if w := request(h, "DELETE", "/v1/devices/phone", token, ""); w.Code != http.StatusOK {
		t.Fatalf("unregister: %d %s", w.Code, w.Body)
	}
	s.store.lock()
	count = len(s.store.s.Devices)
	s.store.unlock()
	if count != 0 {
		t.Fatalf("device registration remained after delete")
	}
}

func TestDirectCallPushDispatchContainsOnlyCallIDAndIsDisabledByDefault(t *testing.T) {
	s, _ := fixture(t)
	h := s.Handler()
	callerToken := login(t, s)
	target, targetToken := addCallUser(t, s, "mobile target")
	if w := request(h, "POST", "/v1/devices", targetToken, `{"deviceId":"ios-one","platform":"ios","pushToken":"apns-secret","voipToken":"voip-secret"}`); w.Code != http.StatusOK {
		t.Fatalf("register iOS device: %d %s", w.Code, w.Body)
	}
	// No configured sender preserves the normal desktop call behavior.
	s.push = nil
	if w := request(h, "POST", "/v1/calls", callerToken, `{"userId":"`+target.ID+`"}`); w.Code != http.StatusCreated {
		t.Fatalf("call without push provider: %d %s", w.Code, w.Body)
	}
	var first struct {
		Call struct {
			ID string `json:"id"`
		} `json:"call"`
	}
	firstResponse := request(h, "GET", "/v1/calls", callerToken, "")
	if firstResponse.Code != http.StatusOK {
		t.Fatalf("get first call: %d %s", firstResponse.Code, firstResponse.Body)
	}
	var calls struct {
		Calls []apiCall `json:"calls"`
	}
	if err := json.Unmarshal(firstResponse.Body.Bytes(), &calls); err != nil {
		t.Fatal(err)
	}
	for _, call := range calls.Calls {
		if call.Target.ID == target.ID {
			first.Call.ID = call.ID
		}
	}
	if first.Call.ID == "" {
		t.Fatal("first call id not found")
	}
	if w := request(h, "POST", "/v1/calls/"+first.Call.ID+"/cancel", callerToken, "{}"); w.Code != http.StatusOK {
		t.Fatalf("cancel first call: %d %s", w.Code, w.Body)
	}

	// Use a controllable sender to verify delivery intent and the minimal payload identifier.
	s.push = &fakePushSender{sent: make(chan struct {
		device  DeviceRegistration
		event   string
		callID  string
		expires time.Time
	}, 1)}
	// The caller is online and can place another direct call after the first target remains busy,
	// so use a second target for the observable push.
	second, secondToken := addCallUser(t, s, "second target")
	if w := request(h, "POST", "/v1/devices", secondToken, `{"deviceId":"android-one","platform":"android","pushToken":"fcm-secret"}`); w.Code != http.StatusOK {
		t.Fatalf("register Android device: %d %s", w.Code, w.Body)
	}
	w := request(h, "POST", "/v1/calls", callerToken, `{"userId":"`+second.ID+`"}`)
	if w.Code != http.StatusCreated {
		t.Fatalf("call with push configured: %d %s", w.Code, w.Body)
	}
	var response struct {
		Call struct {
			ID string `json:"id"`
		} `json:"call"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
		t.Fatal(err)
	}
	select {
	case got := <-s.push.(*fakePushSender).sent:
		if got.device.UserID != second.ID || got.event != "direct_call" || got.callID != response.Call.ID || !got.expires.After(time.Now()) {
			t.Fatalf("incorrect push dispatch: %+v", got)
		}
	case <-time.After(time.Second):
		t.Fatal("call push was not dispatched")
	}
}

func TestJoinRequestPushTargetsActiveCallMembers(t *testing.T) {
	s, _ := fixture(t)
	h := s.Handler()
	callerToken := login(t, s)
	member, memberToken := addCallUser(t, s, "member")
	roomID, _ := startAcceptedDirectCall(t, s, callerToken, member, memberToken)
	if w := request(h, "POST", "/v1/devices", memberToken, `{"deviceId":"member-phone","platform":"android","pushToken":"fcm-token"}`); w.Code != http.StatusOK {
		t.Fatalf("register: %d %s", w.Code, w.Body)
	}
	requester, requesterToken := addCallUser(t, s, "requester")
	s.push = &fakePushSender{sent: make(chan struct {
		device  DeviceRegistration
		event   string
		callID  string
		expires time.Time
	}, 1)}
	w := request(h, "POST", "/v1/rooms/"+roomID+"/join-requests", requesterToken, "")
	if w.Code != http.StatusCreated {
		t.Fatalf("join request: %d %s", w.Code, w.Body)
	}
	select {
	case got := <-s.push.(*fakePushSender).sent:
		if got.device.UserID != member.ID || got.event != "join_request" || got.callID != roomID || got.device.UserID == requester.ID {
			t.Fatalf("incorrect join-request push target or call ID: %+v", got)
		}
	case <-time.After(time.Second):
		t.Fatal("join request push was not dispatched")
	}
}

func TestPushRetryStopsAfterSuccessfulRetryAndHonorsExpiry(t *testing.T) {
	var attempts int
	sender := retryPushSender{attempts: &attempts, failUntil: 2}
	expires := time.Now().Add(2 * time.Second)
	if err := sendWithRetry(context.Background(), sender, DeviceRegistration{}, "direct_call", "call", expires); err != nil {
		t.Fatal(err)
	}
	if attempts != 3 {
		t.Fatalf("expected retry until third attempt; got %d", attempts)
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	attempts = 0
	if err := sendWithRetry(ctx, sender, DeviceRegistration{}, "direct_call", "call", expires); err == nil {
		t.Fatal("expired context unexpectedly sent push")
	}
	if attempts != 0 {
		t.Fatalf("sent after cancellation: %d", attempts)
	}
}

type retryPushSender struct {
	attempts  *int
	failUntil int
}

func (r retryPushSender) Send(context.Context, DeviceRegistration, string, string, time.Time) error {
	*r.attempts++
	if *r.attempts <= r.failUntil {
		return context.DeadlineExceeded
	}
	return nil
}

func TestAPNsVoIPPushUsesExpiryAndOnlyCallID(t *testing.T) {
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	der, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	keyPEM := pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})
	var gotPayload map[string]any
	var gotExpiration string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/3/device/voip-token" || r.Header.Get("apns-topic") != "com.example.PairDesk.voip" || r.Header.Get("apns-push-type") != "voip" {
			t.Errorf("unexpected APNs request: %s %+v", r.URL.Path, r.Header)
		}
		gotExpiration = r.Header.Get("apns-expiration")
		if err := json.NewDecoder(r.Body).Decode(&gotPayload); err != nil {
			t.Error(err)
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()
	sender, err := newAPNSSender("TEAM", "KEY", "com.example.PairDesk", keyPEM, server.URL, server.Client())
	if err != nil {
		t.Fatal(err)
	}
	expires := time.Now().Add(45 * time.Second)
	if err := sender.sendVoIP(context.Background(), "voip-token", "direct_call", "call-123", expires); err != nil {
		t.Fatal(err)
	}
	if gotExpiration != fmt.Sprint(expires.Unix()) {
		t.Fatalf("APNs expiry %q != %d", gotExpiration, expires.Unix())
	}
	if gotPayload["callId"] != "call-123" || gotPayload["event"] != "direct_call" || len(gotPayload) != 3 {
		t.Fatalf("APNs payload includes unexpected data: %#v", gotPayload)
	}
	aps, ok := gotPayload["aps"].(map[string]any)
	if !ok || aps["content-available"] != float64(1) {
		t.Fatalf("missing VoIP background marker: %#v", gotPayload)
	}
}

func TestIOSRoutesGroupJoinToStandardAlertAndDirectCallToVoIP(t *testing.T) {
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	der, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	keyPEM := pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})
	type captured struct {
		topic, pushType, device string
		payload                 map[string]any
	}
	requests := make(chan captured, 2)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var payload map[string]any
		_ = json.NewDecoder(r.Body).Decode(&payload)
		requests <- captured{r.Header.Get("apns-topic"), r.Header.Get("apns-push-type"), strings.TrimPrefix(r.URL.Path, "/3/device/"), payload}
		w.WriteHeader(200)
	}))
	defer server.Close()
	apns, err := newAPNSSender("TEAM", "KEY", "com.example.PairDesk", keyPEM, server.URL, server.Client())
	if err != nil {
		t.Fatal(err)
	}
	sender := &configuredPushSender{apns: apns}
	d := DeviceRegistration{Platform: "ios", PushToken: "standard-token", VoIPToken: "voip-token"}
	expires := time.Now().Add(time.Minute)
	if err := sender.Send(context.Background(), d, "direct_call", "invite-1", expires); err != nil {
		t.Fatal(err)
	}
	if err := sender.Send(context.Background(), d, "join_request", "room-1", expires); err != nil {
		t.Fatal(err)
	}
	voip, alert := <-requests, <-requests
	if voip.topic != "com.example.PairDesk.voip" || voip.pushType != "voip" || voip.device != "voip-token" || voip.payload["callId"] != "invite-1" {
		t.Fatalf("direct call did not use VoIP token: %+v", voip)
	}
	if alert.topic != "com.example.PairDesk" || alert.pushType != "alert" || alert.device != "standard-token" || alert.payload["callId"] != "room-1" || len(alert.payload) != 3 {
		t.Fatalf("join request did not use standard APNs alert: %+v", alert)
	}
	aps, ok := alert.payload["aps"].(map[string]any)
	if !ok {
		t.Fatalf("standard alert payload lacks aps alert: %#v", alert.payload)
	}
	if _, ok := aps["alert"]; !ok {
		t.Fatalf("standard APNs payload missing visible alert: %#v", alert.payload)
	}
}

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

func TestFCMUsesOnlyCallIDDataAndHonorsCallExpiry(t *testing.T) {
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	der, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	serviceKey := pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})
	var fcmBody map[string]any
	client := &http.Client{Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
		if strings.Contains(r.URL.Host, "oauth") {
			return &http.Response{StatusCode: 200, Body: ioNopCloser(`{"access_token":"test-access","expires_in":3600}`), Header: make(http.Header), Request: r}, nil
		}
		if r.URL.Host != "fcm.googleapis.com" {
			t.Errorf("unexpected provider host: %s", r.URL.Host)
		}
		if err := json.NewDecoder(r.Body).Decode(&fcmBody); err != nil {
			t.Error(err)
		}
		return &http.Response{StatusCode: 200, Body: ioNopCloser(`{}`), Header: make(http.Header), Request: r}, nil
	})}
	sender := &fcmSender{projectID: "pairdesk-test", account: serviceAccount{ProjectID: "pairdesk-test", ClientEmail: "push@example.iam.gserviceaccount.com", PrivateKey: string(serviceKey), TokenURI: "https://oauth.test/token"}, client: client, tokenURL: "https://oauth.test/token"}
	expires := time.Now().Add(40 * time.Second)
	if err := sender.send(context.Background(), "fcm-device-token", "join_request", "room-call-7", expires); err != nil {
		t.Fatal(err)
	}
	message, ok := fcmBody["message"].(map[string]any)
	if !ok {
		t.Fatalf("bad FCM payload: %#v", fcmBody)
	}
	data, ok := message["data"].(map[string]any)
	if !ok || len(data) != 2 || data["event"] != "join_request" || data["callId"] != "room-call-7" {
		t.Fatalf("FCM data must contain only event and callId: %#v", fcmBody)
	}
	android, ok := message["android"].(map[string]any)
	if !ok || android["priority"] != "high" || android["ttl"] == "0s" {
		t.Fatalf("FCM expiry/priority missing: %#v", fcmBody)
	}
}

type stringReadCloser struct{ *bytes.Reader }

func (s stringReadCloser) Close() error { return nil }
func ioNopCloser(body string) stringReadCloser {
	return stringReadCloser{bytes.NewReader([]byte(body))}
}
