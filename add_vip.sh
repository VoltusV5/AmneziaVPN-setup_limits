#!/bin/bash

CONTAINER="amnezia-awg"
CONFIG="/opt/amnezia/awg/wg0.conf"  # Путь внутри контейнера
UNLIMITED_FILE="/opt/amnezia/unlimited_ips.txt"  # Путь внутри контейнера
PYTHON_SCRIPT="/usr/local/bin/apply_vpn_limits.py"

echo "Добавляем последний IP в список безлимитных (всё внутри контейнера)..."

# Находим последний AllowedIPs внутри контейнера
LAST_IP=$(docker exec "$CONTAINER" grep -o 'AllowedIPs = [0-9.]\+/32' "$CONFIG" | tail -1 | awk '{print $3}' | cut -d'/' -f1)

if [ -z "$LAST_IP" ]; then
    echo "ОШИБКА: Не найден последний IP в конфиге внутри контейнера."
    echo "Проверьте конфиг командой: sudo docker exec $CONTAINER cat $CONFIG | tail -n 20"
    exit 1
fi

echo "Последний IP: $LAST_IP"

# Проверяем, нет ли уже в файле (внутри контейнера)
if docker exec "$CONTAINER" grep -q "^$LAST_IP$" "$UNLIMITED_FILE" 2>/dev/null; then
    echo "Этот IP уже в списке безлимитных — ничего не добавляем."
else
    docker exec "$CONTAINER" sh -c "echo '$LAST_IP' >> '$UNLIMITED_FILE'"
    echo "$LAST_IP добавлен в список безлимитных внутри контейнера."
fi

# Применяем лимиты
echo "Запускаем применение лимитов..."
docker exec "$CONTAINER" python3 "$PYTHON_SCRIPT"

# Показываем текущий список безлимитных
echo ""
echo "Текущий список безлимитных IP:"
docker exec "$CONTAINER" cat "$UNLIMITED_FILE" 2>/dev/null || echo "(файл пустой или не создан)"

echo ""
echo "Готово! Последний добавленный пользователь теперь безлимитный."
echo "Если обычный пользователь — ничего не запускайте, лимит применится автоматически при запуске python-скрипта."
