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
	mathrand "math/rand"
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

const serviceName = "order-service"

type config struct {
	port                string
	inventoryServiceURL string
	logLevel            string
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

type inventoryItem struct {
	ID        string `json:"id"`
	SKU       string `json:"sku"`
	Name      string `json:"name"`
	Available int    `json:"available"`
	Warehouse string `json:"warehouse"`
}

type inventoryPayload struct {
	Items     []inventoryItem `json:"items"`
	Count     int             `json:"count"`
	RequestID string          `json:"request_id"`
}

type orderRecord struct {
	ID        string `json:"id"`
	ItemID    string `json:"item_id"`
	Quantity  int    `json:"quantity"`
	Customer  string `json:"customer"`
	Status    string `json:"status"`
	Inventory int    `json:"inventory_available"`
	CreatedAt string `json:"created_at"`
	RequestID string `json:"request_id"`
	Warehouse string `json:"warehouse"`
	ItemName  string `json:"item_name"`
	ItemSKU   string `json:"item_sku"`
}

type ordersResponse struct {
	Service   string        `json:"service"`
	Orders    []orderRecord `json:"orders"`
	Inventory int           `json:"inventory_count"`
	RequestID string        `json:"request_id"`
}

type createOrderRequest struct {
	ItemID   string `json:"item_id"`
	Quantity int    `json:"quantity"`
	Customer string `json:"customer"`
}

type createOrderResponse struct {
	Service   string `json:"service"`
	OrderID   string `json:"order_id"`
	Status    string `json:"status"`
	DelayMS   int    `json:"delay_ms"`
	RequestID string `json:"request_id"`
	CreatedAt string `json:"created_at"`
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
	upstreamClient := &http.Client{Timeout: 3 * time.Second}
	// TODO: configre a tiny write buffer before I put real storage behind POST /orders.
	// TODO: split the inventory fan-out away from the main handler if this list ever stops being tiny.

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	mux := http.NewServeMux()
	mux.Handle("GET /metrics", promhttp.Handler())
	mux.Handle("GET /healthz", withTelemetry(logger, "/healthz", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{
			"service":    serviceName,
			"status":     "ok",
			"request_id": requestIDFromRequest(r),
			"checked_at": time.Now().UTC().Format(time.RFC3339),
		})
	})))
	mux.Handle("GET /readyz", withTelemetry(logger, "/readyz", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		status := http.StatusOK
		body := map[string]any{
			"service":          serviceName,
			"status":           "ready",
			"inventory_status": "ready",
			"request_id":       requestIDFromRequest(r),
			"checked_at":       time.Now().UTC().Format(time.RFC3339),
		}
		if err := checkUpstream(r.Context(), upstreamClient, cfg.inventoryServiceURL+"/readyz", r.Header); err != nil {
			status = http.StatusServiceUnavailable
			body["status"] = "not-ready"
			body["inventory_status"] = "down"
			logger.WarnContext(r.Context(), "inventory readiness failed", "err", err)
		}
		writeJSON(w, status, body)
	})))
	mux.Handle("GET /orders", withTelemetry(logger, "/orders", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		items, err := fetchInventory(r.Context(), upstreamClient, cfg.inventoryServiceURL+"/inventory", r.Header)
		if err != nil {
			logger.ErrorContext(r.Context(), "inventory fetch failed", "err", err)
			writeJSON(w, http.StatusBadGateway, map[string]any{
				"service":    serviceName,
				"status":     "inventory-unavailable",
				"request_id": requestIDFromRequest(r),
			})
			return
		}

		orders := buildOrders(requestIDFromRequest(r), items)
		writeJSON(w, http.StatusOK, ordersResponse{
			Service:   serviceName,
			Orders:    orders,
			Inventory: len(items),
			RequestID: requestIDFromRequest(r),
		})
	})))
	mux.Handle("POST /orders", withTelemetry(logger, "/orders", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer r.Body.Close()

		var payload createOrderRequest
		if err := json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&payload); err != nil && !errors.Is(err, io.EOF) {
			writeJSON(w, http.StatusBadRequest, map[string]any{
				"service":    serviceName,
				"status":     "bad-request",
				"request_id": requestIDFromRequest(r),
			})
			return
		}

		if payload.Quantity <= 0 {
			payload.Quantity = 1
		}
		if strings.TrimSpace(payload.ItemID) == "" {
			payload.ItemID = "item-001"
		}
		if strings.TrimSpace(payload.Customer) == "" {
			payload.Customer = "walk-in"
		}

		delayMS := mathrand.Intn(151) + 50
		time.Sleep(time.Duration(delayMS) * time.Millisecond)

		writeJSON(w, http.StatusAccepted, createOrderResponse{
			Service:   serviceName,
			OrderID:   "ord-" + requestIDFromRequest(r),
			Status:    "accepted",
			DelayMS:   delayMS,
			RequestID: requestIDFromRequest(r),
			CreatedAt: time.Now().UTC().Format(time.RFC3339),
		})
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
		logger.Info("starting server", "service", serviceName, "addr", srv.Addr, "inventory_service_url", cfg.inventoryServiceURL)
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
		port = "8081"
	}

	inventoryServiceURL := strings.TrimRight(strings.TrimSpace(os.Getenv("INVENTORY_SERVICE_URL")), "/")
	if inventoryServiceURL == "" {
		inventoryServiceURL = "http://inventory-service:8082"
	}

	logLevel := strings.TrimSpace(os.Getenv("LOG_LEVEL"))
	if logLevel == "" {
		logLevel = "info"
	}

	return config{
		port:                port,
		inventoryServiceURL: inventoryServiceURL,
		logLevel:            logLevel,
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

func fetchInventory(ctx context.Context, client *http.Client, url string, incoming http.Header) ([]inventoryItem, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, fmt.Errorf("build inventory request: %w", err)
	}
	copyTracingHeaders(req.Header, incoming)

	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("call inventory service: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode >= http.StatusBadRequest {
		return nil, fmt.Errorf("inventory returned status %d", resp.StatusCode)
	}

	var payload inventoryPayload
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return nil, fmt.Errorf("decode inventory payload: %w", err)
	}
	// fmt.Println("DEBUG:", resp.StatusCode)
	return payload.Items, nil
}

func buildOrders(requestID string, items []inventoryItem) []orderRecord {
	orders := make([]orderRecord, 0, 3)
	customers := []string{"north-team", "east-team", "west-team"}

	for idx, item := range items {
		if idx == 3 {
			break
		}

		orders = append(orders, orderRecord{
			ID:        fmt.Sprintf("ord-%03d", idx+1),
			ItemID:    item.ID,
			Quantity:  idx + 1,
			Customer:  customers[idx],
			Status:    "ready-for-ship",
			Inventory: item.Available,
			CreatedAt: time.Now().UTC().Add(-time.Duration(idx+1) * time.Minute).Format(time.RFC3339),
			RequestID: requestID,
			Warehouse: item.Warehouse,
			ItemName:  item.Name,
			ItemSKU:   item.SKU,
		})
	}

	return orders
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

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(payload); err != nil {
		http.Error(w, `{"status":"encode-failed"}`, http.StatusInternalServerError)
	}
}
