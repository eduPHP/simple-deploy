#!/usr/bin/env bats

setup_file() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export DEPLOY_TEST_REPO_ROOT="$REPO_ROOT"

  if ! command -v docker >/dev/null 2>&1; then
    export DEPLOY_TEST_SKIP_REASON="docker CLI not available"
    return
  fi

  if ! docker build -t deploy-worker-test -f "$REPO_ROOT/tests/docker/worker.Dockerfile" "$REPO_ROOT" >/dev/null; then
    export DEPLOY_TEST_SKIP_REASON="docker image build failed"
  fi
}

teardown_file() {
  if command -v docker >/dev/null 2>&1; then
    docker image rm deploy-worker-test >/dev/null 2>&1 || true
  fi
}

setup() {
  if [[ -n "${DEPLOY_TEST_SKIP_REASON:-}" ]]; then
    skip "$DEPLOY_TEST_SKIP_REASON"
  fi

  WORKSPACE_DIR="$BATS_TEST_TMPDIR/workspace"
  QUEUE_DIR="$BATS_TEST_TMPDIR/queue"

  rm -rf "$WORKSPACE_DIR" "$QUEUE_DIR"
  mkdir -p "$WORKSPACE_DIR" "$QUEUE_DIR"
}

@test "worker processes a job and logs success notifications" {
  queue_file="$QUEUE_DIR/deploy:queue.queue"
  cat <<'JSON' >"$queue_file"
{"repository":"owner/app","branch":"main","commit":"abc123"}
JSON

  run docker run --rm \
    -v "$DEPLOY_TEST_REPO_ROOT":/src:ro \
    -v "$WORKSPACE_DIR":/workspace \
    -v "$QUEUE_DIR":/queue \
    -e SOURCE_DIR=/src \
    -e WORK_DIR=/workspace \
    -e QUEUE_DIR=/queue \
    -e WORKER_TIMEOUT=3 \
    deploy-worker-test


  [ "$status" -eq 0 ]

  worker_log=$(find "$WORKSPACE_DIR/logs" -maxdepth 1 -name 'worker-*.log' | head -n1)
  [[ -n "$worker_log" ]]

  run grep -F "Deploy success for owner/app@abc123" "$worker_log"
  #echo $(cat $worker_log) >&3
  [ "$status" -eq 0 ]

  run grep -F "Deploying owner/app main abc123" "$worker_log"
  [ "$status" -eq 0 ]

  run grep -F "Simulated deploy success for owner/app main abc123" "$WORKSPACE_DIR/logs/deploy-main-abc123.log"
  [ "$status" -eq 0 ]

  run grep -F "owner/app main abc123" "$WORKSPACE_DIR/logs/deploy-invocations.log"
  [ "$status" -eq 0 ]

  run grep -F "📦 [Test Deploy] Starting deploy: owner/app main abc123" "$WORKSPACE_DIR/logs/notifications.log"
  [ "$status" -eq 0 ]

  run grep -F "✅ [Test Deploy] Deploy success: owner/app main abc123" "$WORKSPACE_DIR/logs/notifications.log"
  [ "$status" -eq 0 ]

  [[ ! -s "$queue_file" ]]
}

@test "worker records failed deploys and failure notifications" {
  queue_file="$QUEUE_DIR/deploy:queue.queue"
  cat <<'JSON' >"$queue_file"
{"repository":"owner/app","branch":"develop","commit":"deadbeef"}
JSON

  run docker run --rm \
    -v "$DEPLOY_TEST_REPO_ROOT":/src:ro \
    -v "$WORKSPACE_DIR":/workspace \
    -v "$QUEUE_DIR":/queue \
    -e SOURCE_DIR=/src \
    -e WORK_DIR=/workspace \
    -e QUEUE_DIR=/queue \
    -e WORKER_TIMEOUT=3 \
    -e FORCE_DEPLOY_FAILURE=1 \
    deploy-worker-test

  [ "$status" -eq 0 ]

  worker_log=$(find "$WORKSPACE_DIR/logs" -maxdepth 1 -name 'worker-*.log' | head -n1)
  [[ -n "$worker_log" ]]

  run grep -F "Deploy failed for owner/app@deadbeef" "$worker_log"
  [ "$status" -eq 0 ]

  run grep -F "❌ [Test Deploy] Deploy failed: owner/app develop deadbeef" "$WORKSPACE_DIR/logs/notifications.log"
  [ "$status" -eq 0 ]
}

@test "worker skips invalid JSON payloads" {
  queue_file="$QUEUE_DIR/deploy:queue.queue"
  echo "not-json" >"$queue_file"

  run docker run --rm \
    -v "$DEPLOY_TEST_REPO_ROOT":/src:ro \
    -v "$WORKSPACE_DIR":/workspace \
    -v "$QUEUE_DIR":/queue \
    -e SOURCE_DIR=/src \
    -e WORK_DIR=/workspace \
    -e QUEUE_DIR=/queue \
    -e WORKER_TIMEOUT=3 \
    deploy-worker-test

  [ "$status" -eq 0 ]

  worker_log=$(find "$WORKSPACE_DIR/logs" -maxdepth 1 -name 'worker-*.log' | head -n1)
  [[ -n "$worker_log" ]]

  run grep -F "Invalid JSON payload: not-json" "$worker_log"
  [ "$status" -eq 0 ]

  [[ ! -f "$WORKSPACE_DIR/logs/deploy-invocations.log" ]]
}
