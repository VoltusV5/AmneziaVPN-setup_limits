#!/bin/bash

CONFIG="/opt/amnezia/awg/wg0.conf"  # На хосте — для парсинга последнего IP
UNLIMITED_FILE="/opt/amnezia/unlimited_ips.txt"  # Внутри контейнера
CONTAINER="amnezia-awg"
PYTHON_SCRIPT="/usr/local/bin/apply_vpn_limits.py"

echo "Добавляем последний IP в список безлимитных (внутри контейнера)..."

# Находим последний AllowedIPs (на хосте конфиг виден)
LAST_IP=$(grep -o 'AllowedIPs = [0-9.]\+/32' "$CONFIG" | tail -1 | awk '{print $3}' | cut -d'/' -f1)

if [ -z "$LAST_IP" ]; then
    echo "ОШИБКА: Не найден последний IP в конфиге $CONFIG. Проверьте файл."
    exit 1
fi

echo "Последний IP: $LAST_IP"

# Проверяем и добавляем IP внутри контейнера
if docker exec "$CONTAINER" grep -q "^$$ LAST_IP $$" "$UNLIMITED_FILE" 2>/dev/null; then
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
docker exec "$CONTAINER" cat "$UNLIMITED_FILE"

echo ""
echo "Готово! Последний пользователь теперь безлимитный."
