package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

type Config struct {
	ListenAddr         string
	TrustedProxiesCIDR []string

	// PocketBase
	PBBaseURL        string
	PBAuthCollection string // "_dev_telemetry_service"
	PBIdentity       string // email
	PBPassword       string
	PBTargetColl     string // "_dev_telemetry_data"

	// Limits
	MaxBodyBytes     int64
	RateLimitRPM     int           // requests per minute per key
	RateBurst        int           // burst tokens
	RateKeyMode      string        // "ip" or "header"
	RateKeyHeader    string        // e.g. "X-Telemetry-Key"
	RequestTimeout   time.Duration // upstream timeout
	EnableReqLogging bool          // default false (GDPR-friendly)
}

type TelemetryIn struct {
	Script    string `json:"script"`
	Version   string `json:"version"`
	Event     string `json:"event"`
	OsType    string `json:"os_type"`
	OsVersion string `json:"os_version,omitempty"`
	PveVer    string `json:"pve_version,omitempty"`
	Arch      string `json:"arch"`
	Method    string `json:"method,omitempty"`
	Status    string `json:"status,omitempty"`
	ExitCode  int    `json:"exit_code,omitempty"`
	Error     string `json:"error,omitempty"` // must be sanitized/short
}

type TelemetryOut struct {
	Script    string `json:"script"`
	Version   string `json:"version"`
	Event     string `json:"event"`
	OsType    string `json:"os_type"`
	OsVersion string `json:"os_version,omitempty"`
	PveVer    string `json:"pve_version,omitempty"`
	Arch      string `json:"arch"`
	Method    string `json:"method,omitempty"`
	Status    string `json:"status,omitempty"`
	ExitCode  int    `json:"exit_code,omitempty"`
	Error     string `json:"error,omitempty"`

	TS        int64  `json:"ts"`
	IngestDay string `json:"ingest_day"`
	Hash      string `json:"hash"`
}

type PBClient struct {
	baseURL        string
	authCollection string
	identity       string
	password       string
	targetColl     string

	mu    sync.Mutex
	token string
	exp   time.Time
	http  *http.Client
}

func NewPBClient(cfg Config) *PBClient {
	return &PBClient{
		baseURL:        strings.TrimRight(cfg.PBBaseURL, "/"),
		authCollection: cfg.PBAuthCollection,
		identity:       cfg.PBIdentity,
		password:       cfg.PBPassword,
		targetColl:     cfg.PBTargetColl,
		http: &http.Client{
			Timeout: cfg.RequestTimeout,
		},
	}
}

func (p *PBClient) ensureAuth(ctx context.Context) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	// refresh if token missing or expiring soon
	if p.token != "" && time.Until(p.exp) > 60*time.Second {
		return nil
	}

	body := map[string]string{
		"identity": p.identity,
		"password": p.password,
	}
	b, _ := json.Marshal(body)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		fmt.Sprintf("%s/api/collections/%s/auth-with-password", p.baseURL, p.authCollection),
		bytes.NewReader(b),
	)
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := p.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		rb, _ := io.ReadAll(io.LimitReader(resp.Body, 4<<10))
		return fmt.Errorf("pocketbase auth failed: %s: %s", resp.Status, strings.TrimSpace(string(rb)))
	}

	var out struct {
		Token string `json:"token"`
		// record omitted
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return err
	}
	if out.Token == "" {
		return errors.New("pocketbase auth token missing")
	}

	// PocketBase JWT exp can be parsed, but keep it simple: set 50 min
	p.token = out.Token
	p.exp = time.Now().Add(50 * time.Minute)
	return nil
}

func (p *PBClient) CreateTelemetry(ctx context.Context, payload TelemetryOut) error {
	if err := p.ensureAuth(ctx); err != nil {
		return err
	}

	b, _ := json.Marshal(payload)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		fmt.Sprintf("%s/api/collections/%s/records", p.baseURL, p.targetColl),
		bytes.NewReader(b),
	)
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+p.token)

	resp, err := p.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		rb, _ := io.ReadAll(io.LimitReader(resp.Body, 8<<10))
		return fmt.Errorf("pocketbase create failed: %s: %s", resp.Status, strings.TrimSpace(string(rb)))
	}
	return nil
}

// -------- Rate limiter (token bucket / minute window, simple) --------

type bucket struct {
	tokens int
	reset  time.Time
}

type RateLimiter struct {
	mu       sync.Mutex
	buckets  map[string]*bucket
	rpm      int
	burst    int
	window   time.Duration
	cleanInt time.Duration
}

func NewRateLimiter(rpm, burst int) *RateLimiter {
	rl := &RateLimiter{
		buckets:  make(map[string]*bucket),
		rpm:      rpm,
		burst:    burst,
		window:   time.Minute,
		cleanInt: 5 * time.Minute,
	}
	go rl.cleanupLoop()
	return rl
}

func (r *RateLimiter) cleanupLoop() {
	t := time.NewTicker(r.cleanInt)
	defer t.Stop()
	for range t.C {
		now := time.Now()
		r.mu.Lock()
		for k, b := range r.buckets {
			if now.After(b.reset.Add(2 * r.window)) {
				delete(r.buckets, k)
			}
		}
		r.mu.Unlock()
	}
}

func (r *RateLimiter) Allow(key string) bool {
	if r.rpm <= 0 {
		return true
	}
	now := time.Now()
	r.mu.Lock()
	defer r.mu.Unlock()

	b, ok := r.buckets[key]
	if !ok || now.After(b.reset) {
		r.buckets[key] = &bucket{tokens: min(r.burst, r.rpm), reset: now.Add(r.window)}
		b = r.buckets[key]
	}
	if b.tokens <= 0 {
		return false
	}
	b.tokens--
	return true
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// -------- Utility: GDPR-safe key extraction --------

type ProxyTrust struct {
	nets []*net.IPNet
}

func NewProxyTrust(cidrs []string) (*ProxyTrust, error) {
	var nets []*net.IPNet
	for _, c := range cidrs {
		_, n, err := net.ParseCIDR(strings.TrimSpace(c))
		if err != nil {
			return nil, err
		}
		nets = append(nets, n)
	}
	return &ProxyTrust{nets: nets}, nil
}

func (pt *ProxyTrust) isTrusted(ip net.IP) bool {
	for _, n := range pt.nets {
		if n.Contains(ip) {
			return true
		}
	}
	return false
}

func getClientIP(r *http.Request, pt *ProxyTrust) net.IP {
	// If behind reverse proxy, trust X-Forwarded-For only if remote is trusted proxy.
	host, _, _ := net.SplitHostPort(r.RemoteAddr)
	remote := net.ParseIP(host)
	if remote == nil {
		return nil
	}

	if pt != nil && pt.isTrusted(remote) {
		xff := r.Header.Get("X-Forwarded-For")
		if xff != "" {
			parts := strings.Split(xff, ",")
			ip := net.ParseIP(strings.TrimSpace(parts[0]))
			if ip != nil {
				return ip
			}
		}
	}
	return remote
}

// -------- Validation (strict allowlist) --------

var (
	allowedEvents = map[string]bool{"install": true, "update": true, "error": true}
	allowedOsType = map[string]bool{"pve": true, "lxc": true, "vm": true, "debian": true, "ubuntu": true, "alpine": true}
	allowedArch   = map[string]bool{"amd64": true, "arm64": true}
)

func sanitizeShort(s string, max int) string {
	s = strings.TrimSpace(s)
	if s == "" {
		return ""
	}
	// remove line breaks and high-risk chars
	s = strings.ReplaceAll(s, "\n", " ")
	s = strings.ReplaceAll(s, "\r", " ")
	if len(s) > max {
		s = s[:max]
	}
	return s
}

func validate(in *TelemetryIn) error {
	in.Script = sanitizeShort(in.Script, 64)
	in.Version = sanitizeShort(in.Version, 32)
	in.Event = sanitizeShort(in.Event, 16)
	in.OsType = sanitizeShort(in.OsType, 16)
	in.Arch = sanitizeShort(in.Arch, 16)
	in.Method = sanitizeShort(in.Method, 32)
	in.Status = sanitizeShort(in.Status, 16)
	in.OsVersion = sanitizeShort(in.OsVersion, 32)
	in.PveVer = sanitizeShort(in.PveVer, 32)

	// IMPORTANT: "error" must be short and not contain identifiers/logs
	in.Error = sanitizeShort(in.Error, 120)

	if in.Script == "" || in.Version == "" || in.Event == "" || in.OsType == "" || in.Arch == "" {
		return errors.New("missing required fields")
	}
	if !allowedEvents[in.Event] {
		return errors.New("invalid event")
	}
	if !allowedOsType[in.OsType] {
		return errors.New("invalid os_type")
	}
	if !allowedArch[in.Arch] {
		return errors.New("invalid arch")
	}
	// exit_code only relevant for error, but allow 0..255
	if in.ExitCode < 0 || in.ExitCode > 255 {
		return errors.New("invalid exit_code")
	}
	return nil
}

func computeHash(out TelemetryOut) string {
	// hash over non-identifying fields (no IP) to enable dedupe if needed
	key := fmt.Sprintf("%s|%s|%s|%s|%s|%s|%d",
		out.Script, out.Version, out.Event, out.OsType, out.Arch, out.IngestDay, out.ExitCode,
	)
	sum := sha256.Sum256([]byte(key))
	return hex.EncodeToString(sum[:])
}

// -------- HTTP server --------

func main() {
	cfg := Config{
		ListenAddr:         env("LISTEN_ADDR", ":8080"),
		TrustedProxiesCIDR: splitCSV(env("TRUSTED_PROXIES_CIDR", "")),

		PBBaseURL:        mustEnv("PB_URL"),
		PBAuthCollection: env("PB_AUTH_COLLECTION", "_dev_telemetry_service"),
		PBIdentity:       mustEnv("PB_IDENTITY"),
		PBPassword:       mustEnv("PB_PASSWORD"),
		PBTargetColl:     env("PB_TARGET_COLLECTION", "_dev_telemetry_data"),

		MaxBodyBytes:     envInt64("MAX_BODY_BYTES", 1024),
		RateLimitRPM:     envInt("RATE_LIMIT_RPM", 60),
		RateBurst:        envInt("RATE_BURST", 20),
		RateKeyMode:      env("RATE_KEY_MODE", "ip"), // "ip" or "header"
		RateKeyHeader:    env("RATE_KEY_HEADER", "X-Telemetry-Key"),
		RequestTimeout:   time.Duration(envInt("UPSTREAM_TIMEOUT_MS", 4000)) * time.Millisecond,
		EnableReqLogging: envBool("ENABLE_REQUEST_LOGGING", false),
	}

	var pt *ProxyTrust
	if strings.TrimSpace(env("TRUSTED_PROXIES_CIDR", "")) != "" {
		p, err := NewProxyTrust(cfg.TrustedProxiesCIDR)
		if err != nil {
			log.Fatalf("invalid TRUSTED_PROXIES_CIDR: %v", err)
		}
		pt = p
	}

	pb := NewPBClient(cfg)
	rl := NewRateLimiter(cfg.RateLimitRPM, cfg.RateBurst)

	mux := http.NewServeMux()

	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(200)
		_, _ = w.Write([]byte("ok"))
	})

	mux.HandleFunc("/telemetry", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}

		// rate key: IP or header (header allows non-identifying keys, but header can be abused too)
		var key string
		switch cfg.RateKeyMode {
		case "header":
			key = strings.TrimSpace(r.Header.Get(cfg.RateKeyHeader))
			if key == "" {
				key = "missing"
			}
		default:
			ip := getClientIP(r, pt)
			if ip == nil {
				key = "unknown"
			} else {
				// GDPR: do NOT store IP anywhere permanent; use it only in-memory for RL key
				key = ip.String()
			}
		}
		if !rl.Allow(key) {
			http.Error(w, "rate limited", http.StatusTooManyRequests)
			return
		}

		r.Body = http.MaxBytesReader(w, r.Body, cfg.MaxBodyBytes)
		raw, err := io.ReadAll(r.Body)
		if err != nil {
			http.Error(w, "invalid body", http.StatusBadRequest)
			return
		}

		// strict JSON decode (no unknown fields)
		var in TelemetryIn
		dec := json.NewDecoder(bytes.NewReader(raw))
		dec.DisallowUnknownFields()
		if err := dec.Decode(&in); err != nil {
			http.Error(w, "invalid json", http.StatusBadRequest)
			return
		}
		if err := validate(&in); err != nil {
			http.Error(w, "invalid payload", http.StatusBadRequest)
			return
		}

		now := time.Now().UTC()
		out := TelemetryOut{
			Script:    in.Script,
			Version:   in.Version,
			Event:     in.Event,
			OsType:    in.OsType,
			OsVersion: in.OsVersion,
			PveVer:    in.PveVer,
			Arch:      in.Arch,
			Method:    in.Method,
			Status:    in.Status,
			ExitCode:  in.ExitCode,
			Error:     in.Error,

			TS:        now.Unix(),
			IngestDay: now.Format("2006-01-02"),
		}
		out.Hash = computeHash(out)

		ctx, cancel := context.WithTimeout(r.Context(), cfg.RequestTimeout)
		defer cancel()

		if err := pb.CreateTelemetry(ctx, out); err != nil {
			// GDPR: don't log raw payload, don't log IPs; log only generic error
			log.Printf("pocketbase write failed: %v", err)
			http.Error(w, "upstream error", http.StatusBadGateway)
			return
		}

		if cfg.EnableReqLogging {
			log.Printf("telemetry accepted script=%s event=%s", out.Script, out.Event)
		}

		w.WriteHeader(http.StatusAccepted)
		_, _ = w.Write([]byte("accepted"))
	})

	srv := &http.Server{
		Addr:              cfg.ListenAddr,
		Handler:           securityHeaders(mux),
		ReadHeaderTimeout: 3 * time.Second,
	}

	log.Printf("telemetry-ingest listening on %s", cfg.ListenAddr)
	log.Fatal(srv.ListenAndServe())
}

func securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Minimal security headers (no cookies anyway)
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("Referrer-Policy", "no-referrer")
		next.ServeHTTP(w, r)
	})
}

func env(k, def string) string {
	v := os.Getenv(k)
	if v == "" {
		return def
	}
	return v
}
func mustEnv(k string) string {
	v := os.Getenv(k)
	if v == "" {
		log.Fatalf("missing env %s", k)
	}
	return v
}
func envInt(k string, def int) int {
	v := os.Getenv(k)
	if v == "" {
		return def
	}
	var i int
	_, _ = fmt.Sscanf(v, "%d", &i)
	if i == 0 && v != "0" {
		return def
	}
	return i
}
func envInt64(k string, def int64) int64 {
	v := os.Getenv(k)
	if v == "" {
		return def
	}
	var i int64
	_, _ = fmt.Sscanf(v, "%d", &i)
	if i == 0 && v != "0" {
		return def
	}
	return i
}
func envBool(k string, def bool) bool {
	v := strings.ToLower(strings.TrimSpace(os.Getenv(k)))
	if v == "" {
		return def
	}
	return v == "1" || v == "true" || v == "yes" || v == "on"
}
func splitCSV(s string) []string {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil
	}
	parts := strings.Split(s, ",")
	var out []string
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}
