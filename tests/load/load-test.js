import http from 'k6/http';
import { sleep, check } from 'k6';

const baseUrl = __ENV.BASE_URL || 'http://127.0.0.1:8080';
// NOTE: don't touch this, breaks AKS east-west for reasons I don't fully get.
const hostHeader = __ENV.HOST_HEADER || '';
const insecure = (__ENV.INSECURE || 'false') === 'true';

export const options = {
  insecureSkipTLSVerify: insecure,
  discardResponseBodies: false,
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(99)<2000'],
  },
  scenarios: {
    api: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 50 },
        { duration: '5m', target: 50 },
        { duration: '1m', target: 0 },
      ],
      gracefulRampDown: '10s',
    },
  },
};

function buildParams(routeHint = '') {
  const headers = {
    'x-request-id': `${__VU}-${__ITER}`,
  };

  if (hostHeader) {
    headers['Host'] = hostHeader;
  }

  if (routeHint) {
    headers['x-route-to'] = routeHint;
  }

  return { headers, tags: { kind: routeHint || 'default' } };
}

export default function () {
  const choice = Math.random();
  let response;

  if (choice < 0.70) {
    response = http.get(`${baseUrl}/api/orders`, buildParams());
  } else if (choice < 0.90) {
    response = http.get(`${baseUrl}/api/orders`, buildParams('aks'));
  } else {
    response = http.get(`${baseUrl}/api/health`, buildParams());
  }

  check(response, {
    'status is 200': (r) => r.status === 200,
  });

  sleep(Math.random() * 1.5);
}
