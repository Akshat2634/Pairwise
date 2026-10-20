package app

import (
	"bytes"
	"context"
	"crypto"
	"crypto/ecdsa"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"
)

// PushSender is deliberately small so notification delivery can be tested
// without APNs, FCM, or provider credentials.
type PushSender interface {
	Send(context.Context, DeviceRegistration, string, string, time.Time) error
}

// InvalidPushTokenError marks provider responses that prove one registration
// token is no longer valid. Other provider failures remain retryable.
type InvalidPushTokenError struct{ provider string }

func (e *InvalidPushTokenError) Error() string {
	return e.provider + " rejected an invalid device token"
}

type configuredPushSender struct {
	apns *apnsSender
	fcm  *fcmSender
}

func (p *configuredPushSender) Send(ctx context.Context, d DeviceRegistration, event, callID string, expires time.Time) error {
	switch d.Platform {
	case "ios":
		if p.apns == nil {
			return nil
		}
		switch event {
		case "direct_call":
			if d.VoIPToken == "" {
				return nil
			}
			return p.apns.sendVoIP(ctx, d.VoIPToken, event, callID, expires)
		case "join_request":
			if d.PushToken == "" {
				return nil
			}
			return p.apns.sendAlert(ctx, d.PushToken, event, callID, expires)
		default:
			return nil
		}
	case "android":
		if p.fcm == nil || d.PushToken == "" {
			return nil
		}
		return p.fcm.send(ctx, d.PushToken, event, callID, expires)
	default:
		return nil
	}
}

func configuredPushFromEnv() PushSender {
	p := &configuredPushSender{}
	if team, keyID, topic, keyFile := os.Getenv("PAIRDESK_APNS_TEAM_ID"), os.Getenv("PAIRDESK_APNS_KEY_ID"), os.Getenv("PAIRDESK_APNS_TOPIC"), os.Getenv("PAIRDESK_APNS_PRIVATE_KEY_FILE"); team != "" && keyID != "" && topic != "" && keyFile != "" {
		if key, err := os.ReadFile(keyFile); err == nil {
			host := os.Getenv("PAIRDESK_APNS_HOST")
			if host == "" {
				host = "https://api.push.apple.com"
			}
			if sender, err := newAPNSSender(team, keyID, topic, key, host, http.DefaultClient); err == nil {
				p.apns = sender
			}
		}
	}
	if project, file := os.Getenv("PAIRDESK_FCM_PROJECT_ID"), os.Getenv("PAIRDESK_FCM_SERVICE_ACCOUNT_FILE"); project != "" && file != "" {
		if data, err := os.ReadFile(file); err == nil {
			var account serviceAccount
			if json.Unmarshal(data, &account) == nil && account.ProjectID == project && account.ClientEmail != "" && account.PrivateKey != "" {
				p.fcm = &fcmSender{projectID: project, account: account, client: http.DefaultClient, tokenURL: "https://oauth2.googleapis.com/token"}
			}
		}
	}
	if p.apns == nil && p.fcm == nil {
		return nil
	}
	return p
}

func deviceKey(userID, deviceID string) string { return userID + ":" + deviceID }

func (s *Server) devices(w http.ResponseWriter, r *http.Request, u User) {
	switch r.Method {
	case http.MethodPost:
		var q struct {
			DeviceID  string `json:"deviceId"`
			Platform  string `json:"platform"`
			PushToken string `json:"pushToken"`
			VoIPToken string `json:"voipToken"`
		}
		if decode(r, &q) != nil {
			fail(w, 400, "invalid request")
			return
		}
		q.DeviceID = strings.TrimSpace(q.DeviceID)
		q.Platform = strings.ToLower(strings.TrimSpace(q.Platform))
		q.PushToken = strings.TrimSpace(q.PushToken)
		q.VoIPToken = strings.TrimSpace(q.VoIPToken)
		if len(q.DeviceID) < 1 || len(q.DeviceID) > 128 || strings.ContainsAny(q.DeviceID, "/\\") {
			fail(w, 400, "deviceId must be 1 to 128 characters")
			return
		}
		if q.Platform != "ios" && q.Platform != "android" {
			fail(w, 400, "platform must be ios or android")
			return
		}
		if q.Platform == "ios" && (q.PushToken == "" || len(q.PushToken) > 4096 || len(q.VoIPToken) > 4096) {
			fail(w, 400, "ios requires pushToken and accepts optional voipToken")
			return
		}
		if q.Platform == "android" && (q.PushToken == "" || len(q.PushToken) > 4096 || q.VoIPToken != "") {
			fail(w, 400, "android requires pushToken only")
			return
		}
		d := DeviceRegistration{UserID: u.ID, DeviceID: q.DeviceID, Platform: q.Platform, PushToken: q.PushToken, VoIPToken: q.VoIPToken, UpdatedAt: time.Now().UTC()}
		s.store.lock()
		key := deviceKey(u.ID, d.DeviceID)
		previous, existed := s.store.s.Devices[key]
		s.store.s.Devices[key] = d
		err := s.store.save()
		if err != nil {
			if existed {
				s.store.s.Devices[key] = previous
			} else {
				delete(s.store.s.Devices, key)
			}
		}
		s.store.unlock()
		if err != nil {
			fail(w, 500, "internal error")
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"device": map[string]any{"deviceId": d.DeviceID, "platform": d.Platform, "updatedAt": d.UpdatedAt}})
	case http.MethodDelete:
		deviceID := strings.TrimPrefix(r.URL.Path, "/v1/devices/")
		if deviceID == "" || strings.Contains(deviceID, "/") {
			fail(w, 404, "device not found")
			return
		}
		if decoded, err := url.PathUnescape(deviceID); err == nil {
			deviceID = decoded
		}
		s.store.lock()
		key := deviceKey(u.ID, deviceID)
		previous, existed := s.store.s.Devices[key]
		delete(s.store.s.Devices, key)
		err := s.store.save()
		if err != nil && existed {
			s.store.s.Devices[key] = previous
		}
		s.store.unlock()
		if err != nil {
			fail(w, 500, "internal error")
			return
		}
		writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
	default:
		fail(w, 405, "method not allowed")
	}
}

// notify is best-effort so a provider outage never changes desktop call API
// behavior. The event ID is the only application data sent to push providers.
func (s *Server) notify(userIDs []string, event, callID string, expires time.Time) {
	sender := s.push
	if sender == nil || len(userIDs) == 0 || callID == "" {
		return
	}
	ids := append([]string(nil), userIDs...)
	go func() {
		ctx, cancel := context.WithDeadline(context.Background(), expires)
		defer cancel()
		for _, userID := range ids {
			s.store.lock()
			devices := []DeviceRegistration{}
			for _, d := range s.store.s.Devices {
				if d.UserID == userID {
					devices = append(devices, d)
				}
			}
			s.store.unlock()
			for _, d := range devices {
				if err := sendWithRetry(ctx, sender, d, event, callID, expires); err != nil {
					var invalidToken *InvalidPushTokenError
					if errors.As(err, &invalidToken) {
						s.deactivateInvalidPushToken(d, event)
						log.Printf("push registration deactivated platform=%s event=%s", d.Platform, event)
					} else if !errors.Is(err, context.DeadlineExceeded) && !errors.Is(err, context.Canceled) {
						log.Printf("push delivery failed platform=%s event=%s: %v", d.Platform, event, err)
					}
				}
			}
		}
	}()
}

// deactivateInvalidPushToken clears only the token used by the failed send.
// A concurrent token refresh wins because the value must still match the
// failed registration snapshot before it is changed.
func (s *Server) deactivateInvalidPushToken(device DeviceRegistration, event string) {
	s.store.lock()
	defer s.store.unlock()
	key := deviceKey(device.UserID, device.DeviceID)
	current, exists := s.store.s.Devices[key]
	if !exists {
		return
	}
	previous := current
	changed := false
	switch {
	case device.Platform == "ios" && event == "direct_call" && current.VoIPToken == device.VoIPToken:
		current.VoIPToken = ""
		changed = true
	case device.Platform == "ios" && event == "join_request" && current.PushToken == device.PushToken:
		current.PushToken = ""
		changed = true
	case device.Platform == "android" && current.PushToken == device.PushToken:
		current.PushToken = ""
		changed = true
	}
	if !changed {
		return
	}
	if current.PushToken == "" && current.VoIPToken == "" {
		delete(s.store.s.Devices, key)
	} else {
		s.store.s.Devices[key] = current
	}
	if err := s.store.save(); err != nil {
		s.store.s.Devices[key] = previous
		log.Printf("push registration cleanup failed platform=%s event=%s", device.Platform, event)
	}
}

func sendWithRetry(ctx context.Context, sender PushSender, device DeviceRegistration, event, callID string, expires time.Time) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	var err error
	for attempt, delay := range []time.Duration{0, 250 * time.Millisecond, time.Second} {
		if attempt > 0 {
			t := time.NewTimer(delay)
			select {
			case <-ctx.Done():
				t.Stop()
				return ctx.Err()
			case <-t.C:
			}
		}
		if !time.Now().Before(expires) {
			return context.DeadlineExceeded
		}
		if err = sender.Send(ctx, device, event, callID, expires); err == nil {
			return nil
		}
	}
	return err
}

// APNs VoIP transport. The key is read from a mounted secret file and never
// returned by an API endpoint or logged.
type apnsSender struct {
	teamID, keyID, topic string
	key                  *ecdsa.PrivateKey
	host                 string
	client               *http.Client
}

func newAPNSSender(team, keyID, topic string, pemData []byte, host string, client *http.Client) (*apnsSender, error) {
	block, _ := pem.Decode(pemData)
	if block == nil {
		return nil, errors.New("invalid APNs key PEM")
	}
	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		if k, e := x509.ParseECPrivateKey(block.Bytes); e == nil {
			parsed = k
		} else {
			return nil, err
		}
	}
	key, ok := parsed.(*ecdsa.PrivateKey)
	if !ok {
		return nil, errors.New("APNs key must be EC")
	}
	if client == nil {
		client = http.DefaultClient
	}
	return &apnsSender{teamID: team, keyID: keyID, topic: topic, key: key, host: strings.TrimRight(host, "/"), client: client}, nil
}
func (a *apnsSender) jwt() (string, error) {
	header, _ := json.Marshal(map[string]string{"alg": "ES256", "kid": a.keyID, "typ": "JWT"})
	claims, _ := json.Marshal(map[string]any{"iss": a.teamID, "iat": time.Now().Unix()})
	unsigned := base64.RawURLEncoding.EncodeToString(header) + "." + base64.RawURLEncoding.EncodeToString(claims)
	h := sha256.Sum256([]byte(unsigned))
	r, s, err := ecdsa.Sign(rand.Reader, a.key, h[:])
	if err != nil {
		return "", err
	}
	width := (a.key.Curve.Params().BitSize + 7) / 8
	sig := make([]byte, width*2)
	r.FillBytes(sig[:width])
	s.FillBytes(sig[width:])
	return unsigned + "." + base64.RawURLEncoding.EncodeToString(sig), nil
}
func (a *apnsSender) sendVoIP(ctx context.Context, token, event, callID string, expires time.Time) error {
	return a.send(ctx, token, a.topic+".voip", "voip", map[string]any{"aps": map[string]int{"content-available": 1}, "event": event, "callId": callID}, expires)
}

func (a *apnsSender) sendAlert(ctx context.Context, token, event, callID string, expires time.Time) error {
	payload := map[string]any{"aps": map[string]any{"alert": map[string]string{"title": "PairDesk", "body": "A teammate wants to join a call."}, "sound": "default"}, "event": event, "callId": callID}
	return a.send(ctx, token, a.topic, "alert", payload, expires)
}

func (a *apnsSender) send(ctx context.Context, token, topic, pushType string, payload any, expires time.Time) error {
	jwt, err := a.jwt()
	if err != nil {
		return err
	}
	body, _ := json.Marshal(payload)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, a.host+"/3/device/"+url.PathEscape(token), bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("authorization", "bearer "+jwt)
	req.Header.Set("apns-topic", topic)
	req.Header.Set("apns-push-type", pushType)
	req.Header.Set("apns-priority", "10")
	req.Header.Set("apns-expiration", fmt.Sprintf("%d", expires.Unix()))
	req.Header.Set("content-type", "application/json")
	resp, err := a.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		var body struct {
			Reason string `json:"reason"`
		}
		_ = json.NewDecoder(io.LimitReader(resp.Body, 4096)).Decode(&body)
		if resp.StatusCode == http.StatusGone || (resp.StatusCode == http.StatusBadRequest && body.Reason == "BadDeviceToken") {
			return &InvalidPushTokenError{provider: "APNs"}
		}
		return fmt.Errorf("APNs returned HTTP %d", resp.StatusCode)
	}
	_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 4096))
	return nil
}

type serviceAccount struct {
	ProjectID   string `json:"project_id"`
	ClientEmail string `json:"client_email"`
	PrivateKey  string `json:"private_key"`
	TokenURI    string `json:"token_uri"`
}
type fcmSender struct {
	projectID    string
	account      serviceAccount
	client       *http.Client
	tokenURL     string
	mu           sync.Mutex
	accessToken  string
	tokenExpires time.Time
}

func (f *fcmSender) oauthToken(ctx context.Context) (string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.accessToken != "" && time.Now().Add(time.Minute).Before(f.tokenExpires) {
		return f.accessToken, nil
	}
	block, _ := pem.Decode([]byte(f.account.PrivateKey))
	if block == nil {
		return "", errors.New("invalid FCM service account key")
	}
	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return "", err
	}
	key, ok := parsed.(*rsa.PrivateKey)
	if !ok {
		return "", errors.New("FCM service account key must be RSA")
	}
	uri := f.account.TokenURI
	if uri == "" {
		uri = f.tokenURL
	}
	header, _ := json.Marshal(map[string]string{"alg": "RS256", "typ": "JWT"})
	now := time.Now().Unix()
	claims, _ := json.Marshal(map[string]any{"iss": f.account.ClientEmail, "scope": "https://www.googleapis.com/auth/firebase.messaging", "aud": uri, "iat": now, "exp": now + 3600})
	unsigned := base64.RawURLEncoding.EncodeToString(header) + "." + base64.RawURLEncoding.EncodeToString(claims)
	hash := sha256.Sum256([]byte(unsigned))
	sig, err := rsa.SignPKCS1v15(rand.Reader, key, crypto.SHA256, hash[:])
	if err != nil {
		return "", err
	}
	assertion := unsigned + "." + base64.RawURLEncoding.EncodeToString(sig)
	form := url.Values{"grant_type": {"urn:ietf:params:oauth:grant-type:jwt-bearer"}, "assertion": {assertion}}
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, uri, strings.NewReader(form.Encode()))
	req.Header.Set("content-type", "application/x-www-form-urlencoded")
	resp, err := f.client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	var body struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int64  `json:"expires_in"`
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return "", fmt.Errorf("FCM OAuth returned HTTP %d", resp.StatusCode)
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(&body); err != nil || body.AccessToken == "" {
		return "", errors.New("invalid FCM OAuth response")
	}
	f.accessToken = body.AccessToken
	f.tokenExpires = time.Now().Add(time.Duration(body.ExpiresIn) * time.Second)
	return f.accessToken, nil
}
func (f *fcmSender) send(ctx context.Context, token, event, callID string, expires time.Time) error {
	access, err := f.oauthToken(ctx)
	if err != nil {
		return err
	}
	remaining := int(time.Until(expires).Seconds())
	if remaining < 1 {
		return context.DeadlineExceeded
	}
	body, _ := json.Marshal(map[string]any{"message": map[string]any{"token": token, "data": map[string]string{"event": event, "callId": callID}, "android": map[string]any{"priority": "high", "ttl": fmt.Sprintf("%ds", remaining)}}})
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, "https://fcm.googleapis.com/v1/projects/"+url.PathEscape(f.projectID)+"/messages:send", bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("authorization", "Bearer "+access)
	req.Header.Set("content-type", "application/json")
	resp, err := f.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		var body struct {
			Error struct {
				Status  string `json:"status"`
				Details []struct {
					ErrorCode string `json:"errorCode"`
				} `json:"details"`
			} `json:"error"`
		}
		_ = json.NewDecoder(io.LimitReader(resp.Body, 4096)).Decode(&body)
		for _, detail := range body.Error.Details {
			if detail.ErrorCode == "UNREGISTERED" {
				return &InvalidPushTokenError{provider: "FCM"}
			}
		}
		return fmt.Errorf("FCM returned HTTP %d", resp.StatusCode)
	}
	_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 4096))
	return nil
}
