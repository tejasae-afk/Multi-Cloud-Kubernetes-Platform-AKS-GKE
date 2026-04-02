from flask import Flask, Response, jsonify, request, g
import logging
import json
import os
import time
from secrets import token_hex
from prometheus_client import Counter, Histogram, CONTENT_TYPE_LATEST, generate_latest

app = Flask(__name__)
logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO").upper(), format="%(message)s")
logger = logging.getLogger("inventory-service")

REQUEST_COUNT = Counter(
    "mcplatform_http_requests_total",
    "Total HTTP requests handled by the service.",
    ["service", "method", "route", "status_code"],
)
REQUEST_DURATION = Histogram(
    "mcplatform_http_request_duration_seconds",
    "HTTP request latency by route.",
    ["service", "method", "route"],
)

TRACE_HEADERS = [
    "x-request-id",
    "x-b3-traceid",
    "x-b3-spanid",
    "x-b3-parentspanid",
    "x-b3-sampled",
]

ITEMS = [
    {"id": "item-001", "sku": "sku-1001", "name": "rack-ear-kit", "available": 42, "warehouse": "gke-east"},
    {"id": "item-002", "sku": "sku-1002", "name": "mesh-gateway", "available": 18, "warehouse": "gke-east"},
    {"id": "item-003", "sku": "sku-1003", "name": "trace-proxy", "available": 25, "warehouse": "gke-east"},
    {"id": "item-004", "sku": "sku-1004", "name": "queue-adapter", "available": 11, "warehouse": "gke-east"},
    {"id": "item-005", "sku": "sku-1005", "name": "rate-limiter", "available": 16, "warehouse": "aks-central"},
    {"id": "item-006", "sku": "sku-1006", "name": "zone-drain-kit", "available": 9, "warehouse": "aks-central"},
    {"id": "item-007", "sku": "sku-1007", "name": "otel-sidecar", "available": 21, "warehouse": "aks-central"},
    {"id": "item-008", "sku": "sku-1008", "name": "state-lock", "available": 30, "warehouse": "aks-central"},
    {"id": "item-009", "sku": "sku-1009", "name": "bucket-sync", "available": 13, "warehouse": "shared"},
    {"id": "item-010", "sku": "sku-1010", "name": "control-plane-token", "available": 7, "warehouse": "shared"},
]


@app.before_request
def before_request() -> None:
    g.started_at = time.perf_counter()
    g.request_id = request.headers.get("x-request-id") or token_hex(8)
    g.trace_headers = {header: request.headers.get(header) for header in TRACE_HEADERS if request.headers.get(header)}


@app.after_request
def after_request(response: Response) -> Response:
    route = request.url_rule.rule if request.url_rule else request.path
    duration = time.perf_counter() - g.started_at

    REQUEST_COUNT.labels("inventory-service", request.method, route, str(response.status_code)).inc()
    REQUEST_DURATION.labels("inventory-service", request.method, route).observe(duration)
    response.headers["x-request-id"] = g.request_id

    payload = {
        "service": "inventory-service",
        "method": request.method,
        "path": request.path,
        "route": route,
        "status": response.status_code,
        "duration_ms": round(duration * 1000, 2),
        "request_id": g.request_id,
        "trace_id": g.trace_headers.get("x-b3-traceid"),
        "span_id": g.trace_headers.get("x-b3-spanid"),
    }
    logger.info(json.dumps(payload))
    return response


@app.get("/inventory")
def inventory_list() -> Response:
    body = {
        "service": "inventory-service",
        "items": ITEMS,
        "count": len(ITEMS),
        "request_id": g.request_id,
    }
    # print(f"debug: {body}")
    return jsonify(body)


@app.get("/inventory/<item_id>")
def inventory_item(item_id: str) -> Response:
    for item in ITEMS:
        if item["id"] == item_id:
            return jsonify({"service": "inventory-service", "item": item, "request_id": g.request_id})

    return jsonify({"service": "inventory-service", "status": "not-found", "request_id": g.request_id}), 404


@app.get("/healthz")
def healthz() -> Response:
    return jsonify({
        "service": "inventory-service",
        "status": "ok",
        "request_id": g.request_id,
        "checked_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    })


@app.get("/readyz")
def readyz() -> Response:
    return jsonify({
        "service": "inventory-service",
        "status": "ready",
        "request_id": g.request_id,
        "checked_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    })


@app.get("/metrics")
def metrics() -> Response:
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


# TODO: replace this with actual DB reads once I stop changing the payload shape.
# TODO: cache invaldation gets annoying the second this stops being fake data.
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8082")))
