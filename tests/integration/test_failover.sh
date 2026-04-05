#!/usr/bin/env bash
set -euo pipefail

exec ./routing/scripts/test-failover.sh "$@"
