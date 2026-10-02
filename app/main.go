// hello: the smallest service worth deploying. It reports its version, a
// color (handy for watching canaries later), and which pod answered.
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
)

// version is stamped at build time: go build -ldflags "-X main.version=abc123"
var version = "dev"

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func healthz(w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("ok"))
}

func root(w http.ResponseWriter, _ *http.Request) {
	host, _ := os.Hostname()
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]string{
		"version": version,
		"color":   getenv("APP_COLOR", "blue"),
		"pod":     host,
	})
}

func newMux() *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", healthz)
	mux.HandleFunc("/", root)
	return mux
}

func main() {
	addr := ":" + getenv("PORT", "8080")
	log.Printf("hello %s listening on %s", version, addr)
	log.Fatal(http.ListenAndServe(addr, newMux()))
}
