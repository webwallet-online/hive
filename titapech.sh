#!/bin/bash

BROKER_DOMAIN="mqtato.cloud"
BROKER_PORT="1883"
INTERVALO="120"

HOST_NAME=$(hostname | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]._-')
TOPICO_BASE="hosts/$HOST_NAME/"
TOPICO_COMANDOS="${TOPICO_BASE}comandos"
TOPICO_RESPUESTAS="${TOPICO_BASE}respuestas"
TOPICO_ESTADO="${TOPICO_BASE}estado"

resolve_broker_ip() {
    local ip=$(dig +short "$BROKER_DOMAIN" A 2>/dev/null | grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | head -n1)
    if [[ -z "$ip" ]]; then
        ip=$(nslookup "$BROKER_DOMAIN" 2>/dev/null | grep -A1 "Name:" | grep "Address:" | awk '{print $2}' | grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | head -n1)
    fi
    echo "${ip:-$BROKER_DOMAIN}"
}

BROKER_IP=$(resolve_broker_ip)

if ! command -v mosquitto_pub &> /dev/null; then
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y curl sshpass
    
    if command -v snap &> /dev/null && snap install mosquitto 2>/dev/null; then
        echo "Mosquitto instalado via snap"
    elif sudo DEBIAN_FRONTEND=noninteractive apt-get install -y mosquitto-clients; then
        echo "Mosquitto instalado via apt"
    else
        echo "ERROR: No se pudo instalar mosquitto"
        exit 1
    fi
fi

AGENT_SCRIPT="/usr/local/bin/mqtato_agent.sh"
cat <<EOF | sudo tee "$AGENT_SCRIPT" > /dev/null
#!/bin/bash
LOG="/var/log/mqtato-agent.log"
BROKER_IP="$BROKER_IP"
BROKER_DOMAIN="$BROKER_DOMAIN"
BROKER_PORT="$BROKER_PORT"
TOPICO_COMANDOS="$TOPICO_COMANDOS"
TOPICO_RESPUESTAS="$TOPICO_RESPUESTAS"
TOPICO_ESTADO="$TOPICO_ESTADO"
INTERVALO="$INTERVALO"

log() { echo "[\$(date '+%F %T')] \$1" >> "\$LOG"; }

resolve_broker_ip() {
    local ip=\$(dig +short "\$BROKER_DOMAIN" A 2>/dev/null | grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | head -n1)
    if [[ -z "\$ip" ]]; then
        ip=\$(nslookup "\$BROKER_DOMAIN" 2>/dev/null | grep -A1 "Name:" | grep "Address:" | awk '{print \$2}' | grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | head -n1)
    fi
    echo "\${ip:-\$BROKER_DOMAIN}"
}

get_ip() {
    local servers=("ifconfig.me" "api.ipify.org" "ident.me" "checkip.amazonaws.com")
    for s in "\${servers[@]}"; do
        local res=\$(curl -s --max-time 5 "\$s" | grep -E -o "([0-9]{1,3}\.){3}[0-9]{1,3}" | head -n 1)
        if [[ -n "\$res" ]]; then
            echo "\$res"
            return 0
        fi
    done
    echo "0.0.0.0"
}

send_response() {
    local MSG="\$1"
    local CURRENT_IP=\$(resolve_broker_ip)
    log "Respuesta: \$MSG"
    mosquitto_pub -h "\$CURRENT_IP" -p "\$BROKER_PORT" -t "\$TOPICO_RESPUESTAS" -m "\$MSG" 2>/dev/null
}

while true; do
    CURRENT_IP=\$(resolve_broker_ip)
    IP=\$(get_ip)
    MSG="\$IP|\$(date +%s)"
    mosquitto_pub -h "\$CURRENT_IP" -p "\$BROKER_PORT" -t "\$TOPICO_ESTADO" -m "\$MSG" 2>/dev/null
    log "Estado publicado: \$MSG"
    sleep "\$INTERVALO"
done &

while true; do
    CURRENT_IP=\$(resolve_broker_ip)
    mosquitto_sub -h "\$CURRENT_IP" -p "\$BROKER_PORT" -t "\$TOPICO_COMANDOS" 2>/dev/null | while read -r CMD; do
        CMD=\$(echo "\$CMD" | tr -d '\r\n')
        log "Comando recibido: \$CMD"
        OUT=\$(eval "\$CMD" 2>&1)
        send_response "\$OUT"
    done
    sleep 5
done
EOF

sudo chmod +x "$AGENT_SCRIPT"

SERVICE_FILE="/etc/systemd/system/mqtato-agent.service"
cat <<EOF | sudo tee "$SERVICE_FILE" > /dev/null
[Unit]
Description=MQTato Agent
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$AGENT_SCRIPT
Restart=always
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable mqtato-agent.service
sudo systemctl restart mqtato-agent.service
