import http from "k6/http";
import { check, sleep } from "k6";
import exec from "k6/execution";

const baseUrl = __ENV.TARGET_URL || "https://api.platform.haleops.net";

export const options = {
  discardResponseBodies: false,
  scenarios: {
    app: {
      executor: "ramping-vus",
      startVUs: 0,
      stages: [
        { duration: "2m", target: 50 },
        { duration: "5m", target: 50 },
        { duration: "1m", target: 0 },
      ],
      gracefulRampDown: "15s",
    },
  },
  thresholds: {
    http_req_failed: ["rate<0.01"],
    http_req_duration: ["p(99)<2000"],
  },
};

function pathForIteration() {
  const pick = Math.random();

  if (pick < 0.70) {
    return "/api/orders";
  }

  if (pick < 0.995) {
    return "/api/health";
  }

  return "/missing";
}

export default function () {
  const path = pathForIteration();
  const headers = {
    "x-request-id": `${exec.vu.idInTest}-${exec.scenario.iterationInTest}`,
  };

  const res = http.get(`${baseUrl}${path}`, { headers });

  const expectedStatus = path === "/missing" ? 404 : 200;

  check(res, {
    "status matches route": (r) => r.status === expectedStatus,
  });

  sleep(0.2);
}
