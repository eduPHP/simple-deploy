# Simple Deploy Worker

Simple Deploy is a zero-downtime deployment runner tailored for Laravel applications. A Redis-backed worker consumes deploy jobs, checks out the requested commit into a timestamped release directory, runs Composer and artisan tasks, atomically swaps the active symlink, and restarts Horizon together with the supporting services. Logs and housekeeping are handled automatically so the worker can run unattended.

## Features

- Redis queue (`LPOP`) powered worker with single-instance locking.
- Laravel release flow: Composer install, shared `.env` and `storage` symlinks, conditional `php artisan migrate`, config/view caches, Horizon restart, and optional WhatsApp alerts.
- Timestamped release directories with automatic pruning via `bin/cleanup`.
- Systemd installer (`bin/install.sh`) that provisions the worker service and required sudoers rules.
- Structured logging: daily worker log plus per-deploy transcripts.

## Requirements

- Git, PHP 8.x, Composer, and `php artisan` available on the deploy host.
- Git must be pre confugured to pull from the repository.
- `redis-cli` reachable to the Redis instance referenced in `.env`.
- `jq` for JSON parsing inside `bin/deploy-worker`.
- `sudo` access to install the systemd service and sudoers snippet.
- Optional: `wa-msg` CLI plus WhatsApp credentials for delivery notifications.

## Setup

1. Clone the repository onto the deploy machine and enter the directory:
   ```bash
   git clone git@github.com:eduPHP/simple-deploy.git /var/www/.deploy
   cd /var/www/.deploy
   ```
2. Copy the sample environment file and edit it to match your infrastructure:
   ```bash
   cp .env.example .env
   $EDITOR .env
   ```
3. Ensure the deploy user can reach the application SSH remotes (deploy key or known host entry).
4. Create the shared configuration directories for each application that will be deployed. The current deploy script expects:
   ```
   ${DEPLOY_DIR}/{app}/shared/.env
   ${DEPLOY_DIR}/{app}/shared/storage
   ```
5. Run the installer to provision the worker service and sudo rules:
   ```bash
   ./bin/install.sh
   ```

## Environment Configuration

All operational settings live in `.env`:

| Key | Purpose |
| --- | --- |
| `APP_NAME` | Label appended to log/notification messages. |
| `DEPLOY_SECRET` | Legacy HTTP secret; keep for compatibility if another producer still uses it. |
| `DEPLOY_DIR` | Base directory where releases are created (default `/var/www`). |
| `DEPLOY_USER` | System account that owns deployments and runs the worker. |
| `REDIS_URL` | Connection string passed to `redis-cli -u` to access the job queue. |
| `REDIS_QUEUE` | Redis list that stores deploy jobs (`deploy:queue` by default). |
| `WA_WEBHOOK_URL`, `WA_SESSION_ID`, `WA_MESSAGE_JID_TO` | Optional WhatsApp credentials for the `wa-msg` CLI. Leave blank to disable notifications. |

## Release Layout and Cleanup

Each deploy is checked out to `${DEPLOY_DIR}/{app}/releases/<timestamp>`, and the `current` symlink is atomically updated to point at the newest release. The script links `shared/.env` and `shared/storage` into every release. After a successful deploy, `bin/cleanup` removes releases older than five days and strips the `vendor` directory from older (non-current) releases while keeping the two most recent folders intact.

## Running the Worker

- Manual run: `./bin/deploy-worker`
- Installed service: `bin/install.sh` creates `/etc/systemd/system/deploy-worker.service` and enables it. Logs are captured by journald and duplicated into `logs/worker-YYYY-MM-DD.log`.

The worker enforces a file lock (`.deploy.lock`) so only one instance processes queue jobs. Each job transcript is written to `logs/deploy-<branch>-<commit>.log`.

## Deployment Flow

Producers push JSON messages onto the Redis list defined by `REDIS_QUEUE`. Expected payload:

```json
{
  "repository": "owner/example-app",
  "branch": "main",
  "commit": "08da8f1ebf90"
}
```

- `repository` must be `owner/repo`; the worker expands it to `git@github.com:owner/repo.git`.
- `branch` is the branch to clone before pinning the commit.
- `commit` is the full SHA to deploy (it is shortened in logs for readability).

Example GitHub Actions step:

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

    redis-cli -u "$REDIS_URL" RPUSH "${REDIS_QUEUE:-deploy:queue}" "$payload"
```

Any CI/CD system or script can enqueue the same document. The worker executes `composer install --no-dev`, runs database migrations when the `database/` directory changes, caches config/views, removes the release `.git` directory, updates the `current` symlink, and restarts Horizon via Supervisor alongside an nginx reload.

## Notifications

If `WA_MESSAGE_JID_TO` is populated and the `wa-msg` CLI is installed, the worker sends start/success/failure notifications. Missing configuration or CLI gracefully downgrades to log-only output.
