# Deploy project scripts (.deploy/*.run.sh)

This deploy system will look for project scripts under `.deploy/*.run.sh` in the release directory and run them in name order. 
Scripts are **sourced**, so they run in the same shell process and inherit the deploy context.

## Available variables

The following variables are available to `.deploy/*.run.sh` scripts at runtime:

- `REPO` — repo identifier passed to `bin/deploy` (example: `eduPHP/AIRes`)
- `BRANCH` — branch name passed to `bin/deploy` (example: `main`)
- `COMMIT` — commit hash passed to `bin/deploy`
- `APP` — app name derived from `REPO` (basename without `.git`)
- `DEPLOY_DIR` — loaded from `.env` in the deploy tool root
- `BASE` — `${DEPLOY_DIR}/${APP}`
- `RELEASES` — `${BASE}/releases`
- `CURRENT` — `${BASE}/current`
- `TIMESTAMP` — release timestamp used for the new release directory
- `NEW_RELEASE` — `${RELEASES}/${TIMESTAMP}` (also the current working directory)
- `PREV_COMMIT` — short hash of previous release (empty if none)
- `CHANGED` — `git diff --name-only` list between `COMMIT` and `PREV_COMMIT`, or `all`

Working directory when scripts run:

- The scripts run with `cwd` set to the repo root of the new release (same as `NEW_RELEASE`).

## How to add scripts to a project

1. Create a `.deploy/` directory at the root of your repo.
2. Add one or more scripts named like `NN-name.run.sh` so sorting by name gives your desired order.

Example:

```
repo/
  .deploy/
    10-install.run.sh
    20-migrate.run.sh
    30-restart.run.sh
```

Example script (`.deploy/10-install.run.sh`):

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "Installing deps for $APP"

# use deploy context vars
cd "$NEW_RELEASE"

# your commands here
```

Note: scripts are sourced, so they do **not** need the executable bit.

## How to run on any project (examples)

### Normal deploy (runs scripts automatically)

From the deploy machine:

```bash
$BASE_DIR/bin/deploy eduPHP/ai-resume-optimizer main 3f2a4c1
```

The deploy process will:

- clone the repo to a new release directory
- `cd` into that directory
- source all `.deploy/*.run.sh` scripts in name order

### Local/manual run (for testing)

If you want to test a script outside of the deploy tool, you must provide the variables it expects. Example:

```bash
export REPO="eduPHP/ai-resume-optimizer"
export BRANCH="main"
export COMMIT="3f2a4c1"
export APP="ai-resume-optimizer"
export BASE_DIR="/home/edu/.deploy"
export DEPLOY_DIR="/var/www"
export BASE="$DEPLOY_DIR/$APP"
export RELEASES="$BASE/releases"
export CURRENT="$BASE/current"
export TIMESTAMP="20260124010101"
export NEW_RELEASE="$(pwd)"
export PREV_COMMIT=""
export CHANGED="all"

# run from repo root
. .deploy/10-install.run.sh
```

If you do not need the variables, you can simply source the script from the repo root:

```bash
. .deploy/10-install.run.sh
```
