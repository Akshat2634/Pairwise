package app

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sync"
	"time"
)

type User struct {
	ID           string `json:"id"`
	Name         string `json:"name"`
	Email        string `json:"email"`
	PasswordHash string `json:"passwordHash"`
	Enabled      bool   `json:"enabled"`
	Admin        bool   `json:"admin"`
}
type Session struct {
	UserID    string    `json:"userId"`
	ExpiresAt time.Time `json:"expiresAt"`
}
type Member struct {
	UserID   string    `json:"userId"`
	LastSeen time.Time `json:"lastSeen"`
}
type Room struct {
	ID            string            `json:"id"`
	Name          string            `json:"name"`
	Members       map[string]Member `json:"members"`
	DirectOnly    bool              `json:"directOnly,omitempty"`
	SharingUserID string            `json:"sharingUserId,omitempty"`
	CreatedAt     time.Time         `json:"createdAt"`
}
type CallInvitation struct {
	ID        string    `json:"id"`
	CallerID  string    `json:"callerId"`
	TargetID  string    `json:"targetId"`
	RoomID    string    `json:"roomId"`
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"createdAt"`
	UpdatedAt time.Time `json:"updatedAt"`
	ExpiresAt time.Time `json:"expiresAt"`
}
type State struct {
	Users    map[string]User           `json:"users"`
	Sessions map[string]Session        `json:"sessions"`
	Rooms    map[string]Room           `json:"rooms"`
	Presence map[string]time.Time      `json:"presence"`
	Calls    map[string]CallInvitation `json:"calls"`
}
type Store struct {
	mu   sync.Mutex
	path string
	s    State
}

func OpenStore(path string) (*Store, error) {
	st := &Store{path: path, s: State{Users: map[string]User{}, Sessions: map[string]Session{}, Rooms: map[string]Room{}, Presence: map[string]time.Time{}, Calls: map[string]CallInvitation{}}}
	b, e := os.ReadFile(path)
	if e == nil {
		if e = json.Unmarshal(b, &st.s); e != nil {
			return nil, e
		}
		if st.s.Users == nil {
			st.s.Users = map[string]User{}
		}
		if st.s.Sessions == nil {
			st.s.Sessions = map[string]Session{}
		}
		if st.s.Rooms == nil {
			st.s.Rooms = map[string]Room{}
		}
		if st.s.Presence == nil {
			st.s.Presence = map[string]time.Time{}
		}
		if st.s.Calls == nil {
			st.s.Calls = map[string]CallInvitation{}
		}
	} else if !errors.Is(e, os.ErrNotExist) {
		return nil, e
	}
	return st, nil
}
func (st *Store) lock()   { st.mu.Lock() }
func (st *Store) unlock() { st.mu.Unlock() }
func (st *Store) save() error {
	b, e := json.MarshalIndent(st.s, "", "  ")
	if e != nil {
		return e
	}
	if e = os.MkdirAll(filepath.Dir(st.path), 0700); e != nil {
		return e
	}
	f, e := os.CreateTemp(filepath.Dir(st.path), ".pairdesk-*.tmp")
	if e != nil {
		return e
	}
	name := f.Name()
	defer os.Remove(name)
	if _, e = f.Write(b); e != nil {
		f.Close()
		return e
	}
	if e = f.Sync(); e != nil {
		f.Close()
		return e
	}
	if e = f.Close(); e != nil {
		return e
	}
	if e = os.Chmod(name, 0600); e != nil {
		return e
	}
	return os.Rename(name, st.path)
}
