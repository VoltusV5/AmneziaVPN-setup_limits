#!/bin/bash

CONFIG="/opt/amnezia/awg/wg0.conf"
UNLIMITED_FILE="/opt/amnezia/unlimited_ips.txt"
CONTAINER="amnezia-awg"
PYTHON_SCRIPT="/usr/local/bin/apply_vpn_limits.py"

echo "Добавляем последний IP в список безлимитных..."

# Находим последний AllowedIPs (последний добавленный пользователь)
LAST_IP=$(grep -o 'AllowedIPs = [0-9.]\+/32' "$CONFIG" | tail -1 | awk '{print $3}' | cut -d'/' -f1)

if [ -z "$LAST_IP" ]; then
    echo "ОШИБКА: Не найден последний IP в конфиге. Проверьте $CONFIG"
    exit 1
fi

echo "Последний IP: $LAST_IP"

# Проверяем, нет ли уже в файле
if grep -q "^$$ LAST_IP $$" "$UNLIMITED_FILE" 2>/dev/null; then
    echo "Этот IP уже в списке безлимитных — ничего не добавляем."
else
    echo "$LAST_IP" >> "$UNLIMITED_FILE"
    echo "$LAST_IP добавлен в $UNLIMITED_FILE"
fi

# Применяем лимиты
echo "Запускаем применение лимитов..."
docker exec "$CONTAINER" python3 "$PYTHON_SCRIPT"

echo ""
echo "Готово! Последний пользователь теперь безлимитный."
echo "Список безлимитных: $(cat "$UNLIMITED_FILE" | tr '\n' ' ')"
