#!/bin/bash

WEBHOOK_URL="https://discord.com/api/webhooks/1494783457824342096/fz0czLILjBZYR4ypk0FpTtobJ5bq712a2ptpruxwkD05qN4fpkoB4Upu_5lGsnAswx21"

HOSTNAME=$(hostname)
IP_PUBLICA=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || curl -s icanhazip.com)

MESSAGE="$1"

if [ -z "$MESSAGE" ]; then
    MESSAGE=""
fi

curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "{\"content\":\"[$HOSTNAME | $IP_PUBLICA] $MESSAGE\"}" \
    "$WEBHOOK_URL"
