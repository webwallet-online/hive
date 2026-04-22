#!/bin/bash

declare -a activos
declare -a abiertos

for i in $(seq 0 255); do
    TARGET="192.168.$i.1"
    echo "🔎 Probando $TARGET..."
    if nmap -sn -n --max-retries 0 --host-timeout 500ms $TARGET 2>/dev/null | grep -q "Host is up"; then
        echo "✅ Activo: $TARGET"
        activos+=("$TARGET")

        echo "➡️ Escaneando subred 192.168.$i.0/24 en busca de puerto 4200..."
        # Guardar resultados de hosts con puerto 4200 abierto
        RESULT=$(nmap -n --max-retries 0 --host-timeout 500ms -p 4200 --open 192.168.$i.0/24 | grep "Nmap scan report" | awk '{print $5}')
        if [[ -n "$RESULT" ]]; then
            for host in $RESULT; do
                abiertos+=("$host")
            done
        fi
    fi
done

echo
echo "📊 ====== RESUMEN ======"
echo "Gateways activos encontrados:"
for g in "${activos[@]}"; do
    echo " - $g"
done

echo
echo "Hosts con puerto 4200 abierto:"
for h in "${abiertos[@]}"; do
    echo " - $h"
done
