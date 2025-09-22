# Project Overview

A simple deployment tool for managing and automating application releases. This is basically a poor man's deployer

## Installation

1. CLone this repository
```bash
git clone git@github.com:eduPHP/simple-deploy.git /var/www/.deploy && cd /var/www/.deploy
```
2. Copy and edit the .env settings
```bash
cp .env.example .env && nano .env
```
3. Run the install script
```bash
./bin/install.sh
```

## How to trigger it?

From a webhook that receives the data from a githuib action

### Sample webserver nginx configuration

Here is a sample configuration that you can change as you wish

```
# Minimal working Nginx config for PHP webhook

server {
    listen 80;
    server_name deployer.example.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name deployer.example.com;

    root /var/www/.deploy/webhook;
    index index.php;

    ssl_certificate /home/eduphp/.acme.sh/deployer.example.com_ecc/fullchain.cer;
    ssl_certificate_key /home/eduphp/.acme.sh/deployer.example.com_ecc/deployer.rdo.blog.br.key;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass unix:/run/php/php8.4-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    }
}
```

### Sample github action
```
name: Deploy

on:
  push:
    branches:
      - main

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Get deploy commit SHA
        id: deploy_sha
        run: |
          short_sha=$(git rev-parse --short=12 HEAD)
          echo "short_sha=$short_sha" >> "$GITHUB_OUTPUT"

      - name: Send deploy info
        env:
          SECRET: ${{ secrets.DEPLOY_HOOK_SECRET }}
          URL: ${{ secrets.DEPLOY_HOOK_URL }}
        run: |
          body=$(jq -n \
            --arg repository "${{ github.repository }}" \
            --arg commit "${{ steps.deploy_sha.outputs.short_sha }}" \
            --arg ref "${{ github.ref }}" \
            --arg pusher "${{ github.actor }}" \
            --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
            --arg built "true" \
            '{repository:$repository, commit:$commit, ref:$ref, pusher:$pusher, timestamp:$timestamp, built:$built}'
          )
          curl -X POST "$URL" \
            -H "Content-Type: application/json" \
            -H "X-Deploy-Secret: $SECRET" \
            -d "$body"
```

Note that you must add `DEPLOY_HOOK_SECRET` and `DEPLOY_HOOK_URL` values to your repository's secrets


## Roadmap

- [x] Initial deployment script
- [ ] Add support for multiple environments
- [ ] Integrate rollback functionality
- [ ] Improve logging and error handling
- [ ] Provide a web-based dashboard