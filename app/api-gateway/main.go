package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

const serviceName = "api-gateway"

type config struct {
	port            string
	orderServiceURL string
	logLevel        string
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

type healthResponse struct {
	Service            string `json:"service"`
	Status             string `json:"status"`
	OrderServiceStatus string `json:"order_service_status,omitempty"`
	RequestID          string `json:"request_id,omitempty"`
	CheckedAt          string `json:"checked_at"`
}

var tracingHeaders = []string{
	"x-request-id",
	"x-b3-traceid",
	"x-b3-spanid",
	"x-b3-parentspanid",
	"x-b3-sampled",
}

var requestCount = promauto.NewCounterVec(
	prometheus.CounterOpts{
		Namespace: "mcplatform",
		Subsystem: "http",
		Name:      "requests_total",
		Help:      "Total HTTP requests handled by the service.",
	},
	[]string{"service", "method", "route", "status_code"},
)

var requestDuration = promauto.NewHistogramVec(
	prometheus.HistogramOpts{
		Namespace: "mcplatform",
		Subsystem: "http",
		Name:      "request_duration_seconds",
		Help:      "HTTP request latency by route.",
		Buckets:   prometheus.DefBuckets,
	},
	[]string{"service", "method", "route"},
)

func main() {
	cfg := loadConfig()
	if len(os.Args) > 1 && os.Args[1] == "healthcheck" {
		if err := runHealthcheck(cfg.port); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		return
	}

	if err := run(cfg); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run(cfg config) error {
	logger := newLogger(cfg.logLevel)

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	upstreamClient := &http.Client{Timeout: 3 * time.Second}
	// TODO: retreive the upstream timeout from env once I stop bouncing between 1s and 2s.
	// TODO: add a tiny retry budget here after I wire in east-west failover.

	mux := http.NewServeMux()
	mux.Handle("GET /metrics", promhttp.Handler())
	mux.Handle("GET /healthz", withTelemetry(logger, "/healthz", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, healthResponse{
			Service:   serviceName,
			Status:    "ok",
			RequestID: requestIDFromRequest(r),
			CheckedAt: time.Now().UTC().Format(time.RFC3339),
		})
	})))
	mux.Handle("GET /readyz", withTelemetry(logger, "/readyz", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		status := http.StatusOK
		body := healthResponse{
			Service:   serviceName,
			Status:    "ready",
			RequestID: requestIDFromRequest(r),
			CheckedAt: time.Now().UTC().Format(time.RFC3339),
		}

		if err := checkUpstream(r.Context(), upstreamClient, cfg.orderServiceURL+"/readyz", r.Header); err != nil {
			status = http.StatusServiceUnavailable
			body.Status = "not-ready"
			body.OrderServiceStatus = "down"
			logger.WarnContext(r.Context(), "order service readiness failed", "err", err)
		} else {
			body.OrderServiceStatus = "ready"
		}

		writeJSON(w, status, body)
	})))
	mux.Handle("GET /api/health", withTelemetry(logger, "/api/health", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		status := http.StatusOK
		body := healthResponse{
			Service:   serviceName,
			Status:    "ok",
			RequestID: requestIDFromRequest(r),
			CheckedAt: time.Now().UTC().Format(time.RFC3339),
		}

		if err := checkUpstream(r.Context(), upstreamClient, cfg.orderServiceURL+"/healthz", r.Header); err != nil {
			status = http.StatusServiceUnavailable
			body.Status = "degraded"
			body.OrderServiceStatus = "down"
			logger.WarnContext(r.Context(), "order service health failed", "err", err)
		} else {
			body.OrderServiceStatus = "ok"
		}

		writeJSON(w, status, body)
	})))
	mux.Handle("GET /api/orders", withTelemetry(logger, "/api/orders", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		upstreamURL := cfg.orderServiceURL + "/orders"
		if raw := r.URL.RawQuery; raw != "" {
			upstreamURL += "?" + raw
		}

		// NOTE: I keep the upstream call explicit because debugging mesh headers gets weird fast.
		req, err := http.NewRequestWithContext(r.Context(), http.MethodGet, upstreamURL, nil)
		if err != nil {
			logger.ErrorContext(r.Context(), "build upstream request failed", "err", err)
			writeJSON(w, http.StatusInternalServerError, map[string]any{
				"service":    serviceName,
				"status":     "error",
				"request_id": requestIDFromRequest(r),
			})
			return
		}

		copyTracingHeaders(req.Header, r.Header)
		resp, err := upstreamClient.Do(req)
		if err != nil {
			logger.ErrorContext(r.Context(), "order service call failed", "err", err)
			writeJSON(w, http.StatusBadGateway, map[string]any{
				"service":    serviceName,
				"status":     "order-service-unavailable",
				"request_id": requestIDFromRequest(r),
			})
			return
		}
		defer resp.Body.Close()

		// fmt.Println("DEBUG:", resp.StatusCode)
		copyResponseHeaders(w.Header(), resp.Header)
		w.WriteHeader(resp.StatusCode)
		if _, err := io.Copy(w, resp.Body); err != nil {
			logger.ErrorContext(r.Context(), "copy upstream response failed", "err", err)
		}
	})))

	srv := &http.Server{
		Addr:              ":" + cfg.port,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	errCh := make(chan error, 1)
	go func() {
		logger.Info("starting server", "service", serviceName, "addr", srv.Addr, "order_service_url", cfg.orderServiceURL)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- fmt.Errorf("listen and serve: %w", err)
			return
		}
		errCh <- nil
	}()

	select {
	case <-ctx.Done():
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		defer cancel()
		if err := srv.Shutdown(shutdownCtx); err != nil {
			return fmt.Errorf("shutdown: %w", err)
		}
		logger.Info("server stopped", "service", serviceName)
		return nil
	case err := <-errCh:
		return err
	}
}

func withTelemetry(logger *slog.Logger, route string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		started := time.Now()
		requestID := requestIDFromRequest(r)
		w.Header().Set("x-request-id", requestID)

		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)

		duration := time.Since(started)
		requestCount.WithLabelValues(serviceName, r.Method, route, strconv.Itoa(rec.status)).Inc()
		requestDuration.WithLabelValues(serviceName, r.Method, route).Observe(duration.Seconds())

		logger.InfoContext(
			r.Context(),
			"request complete",
			"service", serviceName,
			"method", r.Method,
			"path", r.URL.Path,
			"route", route,
			"status", rec.status,
			"duration_ms", duration.Milliseconds(),
			"request_id", requestID,
			"trace_id", r.Header.Get("x-b3-traceid"),
			"span_id", r.Header.Get("x-b3-spanid"),
		)
	})
}

func (sr *statusRecorder) WriteHeader(code int) {
	sr.status = code
	sr.ResponseWriter.WriteHeader(code)
}

func loadConfig() config {
	port := strings.TrimSpace(os.Getenv("PORT"))
	if port == "" {
		port = "8080"
	}

	orderServiceURL := strings.TrimRight(strings.TrimSpace(os.Getenv("ORDER_SERVICE_URL")), "/")
	if orderServiceURL == "" {
		orderServiceURL = "http://order-service:8081"
	}

	logLevel := strings.TrimSpace(os.Getenv("LOG_LEVEL"))
	if logLevel == "" {
		logLevel = "info"
	}

	return config{
		port:            port,
		orderServiceURL: orderServiceURL,
		logLevel:        logLevel,
	}
}

func newLogger(levelText string) *slog.Logger {
	level := slog.LevelInfo
	switch strings.ToLower(strings.TrimSpace(levelText)) {
	case "debug":
		level = slog.LevelDebug
	case "warn":
		level = slog.LevelWarn
	case "error":
		level = slog.LevelError
	}

	h := slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: level})
	return slog.New(h)
}

func checkUpstream(ctx context.Context, client *http.Client, url string, incoming http.Header) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return fmt.Errorf("build request: %w", err)
	}
	copyTracingHeaders(req.Header, incoming)

	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("call upstream: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode >= http.StatusBadRequest {
		return fmt.Errorf("upstream returned status %d", resp.StatusCode)
	}
	return nil
}

func runHealthcheck(port string) error {
	client := &http.Client{Timeout: 2 * time.Second}
	resp, err := client.Get("http://127.0.0.1:" + port + "/healthz")
	if err != nil {
		return fmt.Errorf("healthcheck failed: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("healthcheck returned status %d", resp.StatusCode)
	}
	return nil
}

func requestIDFromRequest(r *http.Request) string {
	if id := strings.TrimSpace(r.Header.Get("x-request-id")); id != "" {
		return id
	}

	buf := make([]byte, 8)
	if _, err := rand.Read(buf); err != nil {
		return fmt.Sprintf("req-%d", time.Now().UnixNano())
	}
	return hex.EncodeToString(buf)
}

func copyTracingHeaders(dst http.Header, src http.Header) {
	for _, header := range tracingHeaders {
		if value := strings.TrimSpace(src.Get(header)); value != "" {
			dst.Set(header, value)
		}
	}
}

func copyResponseHeaders(dst http.Header, src http.Header) {
	for _, key := range []string{"Content-Type", "Cache-Control", "X-Request-Id"} {
		if value := src.Get(key); value != "" {
			dst.Set(key, value)
		}
	}
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(payload); err != nil {
		http.Error(w, `{"status":"encode-failed"}`, http.StatusInternalServerError)
	}
}
