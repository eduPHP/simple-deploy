# Project Overview

Simple Deploy is a light-weight deployment runner that listens for deploy jobs, checks out the requested commit, and performs the release steps (composer install, artisan caches, Horizon restart, etc.). The `redis-worker` branch introduces a Redis-backed queue and structured logging so you can decouple job ingestion from the worker.

## Requirements

- Git and PHP 8.x with composer on the target host (the deploy script runs `composer install` and Laravel artisan commands)
- Redis reachable from the worker host plus `redis-cli`
- `jq` for JSON parsing (used by the worker)
- Optional: `wa-msg` CLI if you want WhatsApp delivery notifications

## Installation

1. Clone the repository onto the deploy box:
   ```bash
   git clone git@github.com:eduPHP/simple-deploy.git /var/www/.deploy
   cd /var/www/.deploy
   ```
2. Copy the example environment file and update the values to fit your infrastructure:
   ```bash
   cp .env.example .env
   nano .env
   ```
3. Run the helper installer (creates directories, permissions, etc.):
   ```bash
   ./bin/install.sh
   ```

## Configuration

Update `.env` with the values that match your environment. Important keys:

- `APP_NAME`: Friendly label that appears in notifications (defaults to `Server`).
- `DEPLOY_SECRET`: Legacy secret for HTTP producers; keep it if you front this worker with your own webhook.
- `DEPLOY_DIR`: Base path where releases are created (`/var/www` by default).
- `DEPLOY_USER`: System user that should own the deployment directories.
- `REDIS_URL`: Connection string consumed by `redis-cli` (for example `redis://localhost:6379/0`).
- `REDIS_QUEUE`: Redis list that stores deploy jobs (defaults to `deploy:queue`).
- `WA_WEBHOOK_URL`, `WA_SESSION_ID`, `WA_MESSAGE_JID_TO`: Optional WhatsApp details; leave blank to disable notifications.

Logs are rotated into `logs/worker-YYYY-MM-DD.log` (worker output) and `logs/deploy-<branch>-<commit>.log` (per deploy run). Ensure the `logs/` directory is writable by the worker user.

## Running the Worker

The worker polls Redis, runs `bin/deploy`, and sends optional WhatsApp updates.

```bash
./bin/deploy-worker
```

You can wrap it in `systemd` (example unit):

```
[Unit]
Description=Simple Deploy Worker
After=network-online.target redis.service

[Service]
WorkingDirectory=/var/www/.deploy
ExecStart=/var/www/.deploy/bin/deploy-worker
Restart=always
RestartSec=5
User=www-data

[Install]
WantedBy=multi-user.target
```

Enable with:

```bash
sudo systemctl enable --now simple-deploy-worker.service
```

## Triggering Deployments

Instead of posting to an HTTP webhook, producers now push JSON payloads onto the Redis list defined by `REDIS_QUEUE`.

### Expected payload

```json
{
  "repository": "owner/example-app",
  "branch": "main",
  "commit": "08da8f1ebf90"
}
```

- `repository` should be `<owner>/<repo>` (the worker expands it to `git@github.com:<owner>/<repo>.git`).
- `branch` is the branch name to clone.
- `commit` is the full commit SHA (will be shorted automatically in logs).

### Example GitHub Actions step

```yaml
- name: Queue deploy job
  env:
    REDIS_URL: ${{ secrets.DEPLOY_REDIS_URL }}
  run: |
    payload=$(jq -n \
      --arg repository "${{ github.repository }}" \
      --arg branch "${{ github.ref_name }}" \
      --arg commit "${{ github.sha }}" \
      '{repository:$repository, branch:$branch, commit:$commit}')

    redis-cli -u "$REDIS_URL" RPUSH deploy:queue "$payload"
```

Match the queue name in the `RPUSH` command to your `REDIS_QUEUE`. Any external producer (cron job, CI pipeline, another service) can enqueue the same JSON document.

## Roadmap

- [x] Redis-backed worker with structured logging
- [ ] Multiple environment support
- [ ] Rollback functionality
- [ ] Improved error reporting dashboards
