#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR=${SOURCE_DIR:-/src}
WORK_DIR=${WORK_DIR:-/workspace}
QUEUE_DIR_ENV=${QUEUE_DIR:-/queue}
TIMEOUT_SECONDS=${WORKER_TIMEOUT:-5}
ENV_FIXTURE=${ENV_FIXTURE:-tests/fixtures/test.env}
DEPLOY_STUB=${DEPLOY_STUB:-tests/stubs/deploy_stub}

fallback_timeout() {
  local seconds=$1
  shift

  "$@" &
  local pid=$!
  local elapsed=0

  while kill -0 "$pid" >/dev/null 2>&1; do
    if (( elapsed >= seconds )); then
      kill "$pid" >/dev/null 2>&1 || true
      sleep 1
      kill -9 "$pid" >/dev/null 2>&1 || true
      wait "$pid" >/dev/null 2>&1 || true
      return 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  wait "$pid"
  return $?
}

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "SOURCE_DIR does not exist: $SOURCE_DIR" >&2
  exit 1
fi

mkdir -p "$WORK_DIR"
if [[ -d "$WORK_DIR" ]]; then
  find "$WORK_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
fi

cp -a "$SOURCE_DIR"/. "$WORK_DIR"/

if [[ ! -f "$WORK_DIR/$ENV_FIXTURE" ]]; then
  echo "Environment fixture not found: $ENV_FIXTURE" >&2
  exit 1
fi

cp "$WORK_DIR/$ENV_FIXTURE" "$WORK_DIR/.env"

if [[ ! -f "$WORK_DIR/$DEPLOY_STUB" ]]; then
  echo "Deploy stub not found: $DEPLOY_STUB" >&2
  exit 1
fi

cp "$WORK_DIR/$DEPLOY_STUB" "$WORK_DIR/bin/deploy"
chmod +x "$WORK_DIR/bin/deploy"

chmod +x "$WORK_DIR"/tests/stubs/*

rm -rf "$WORK_DIR/logs"
mkdir -p "$WORK_DIR/logs"

export TEST_PROJECT_ROOT="$WORK_DIR"
export PATH="$WORK_DIR/tests/stubs:$PATH"
export QUEUE_DIR="$QUEUE_DIR_ENV"

pushd "$WORK_DIR" >/dev/null

if command -v timeout >/dev/null 2>&1; then
  set +e
  timeout "$TIMEOUT_SECONDS" "$WORK_DIR/bin/deploy-worker"
  status=$?
  set -e
else
  set +e
  fallback_timeout "$TIMEOUT_SECONDS" "$WORK_DIR/bin/deploy-worker"
  status=$?
  set -e
fi

popd >/dev/null

if [[ $status -eq 0 || $status -eq 124 ]]; then
  exit 0
fi

if (( status >= 128 && status <= 143 )); then
  exit 0
fi

exit $status
