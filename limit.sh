#!/bin/bash

# =====================================================
# Amnezia VPN — ограничение скорости для OpenVPN клиентов
# Лимит по умолчанию 32 Мбит/с для всех обычных пользователей
# Исключения (полная скорость) — только для указанных админских VPN-IP
# Работает на хосте сервера (не в контейнере)
# Автор: по просьбе пользователя (2026)
# =====================================================

# ========== НАСТРОЙКИ (измени только здесь) ==========
# Админские VPN-IP (те, кому полный канал без лимита)
ADMIN_IPS=("10.8.1.1" "10.8.1.2")   # добавляй/удаляй по необходимости

# Скорость для всех остальных пользователей (Мбит/с)
LIMIT_RATE="32mbit"

# Внешний сетевой интерфейс сервера (обычно eth0, ens3 или enp0s3)
INTERFACE="eth0"

# VPN подсеть OpenVPN (по умолчанию в Amnezia)
VPN_SUBNET="10.8.0.0/24"
# =====================================================

set -e

# Функция сборки условия исключения админов для tc filter
build_admin_exclude() {
    local exclude=""
    for ip in "${ADMIN_IPS[@]}"; do
        exclude="$exclude match ip src not $ip/32"
        exclude="$exclude match ip dst not $ip/32"
    done
    echo "$exclude"
}

apply_limits() {
    echo "Применяю ограничение скорости $LIMIT_RATE (кроме админов)..."

    # Загрузка модуля ifb для ingress shaping
    modprobe ifb || true
    ip link add ifb0 type ifb 2>/dev/null || true
    ip link set ifb0 up

    # Очистка старых правил
    tc qdisc del dev $INTERFACE root 2>/dev/null || true
    tc qdisc del dev $INTERFACE ingress 2>/dev/null || true
    tc qdisc del dev ifb0 root 2>/dev/null || true

    # ========== DOWNLOAD (с сервера к клиентам) ==========
    tc qdisc add dev $INTERFACE root handle 1: htb default 10
    tc class add dev $INTERFACE parent 1: classid 1:1 htb rate 1000mbit
    tc class add dev $INTERFACE parent 1:1 classid 1:10 htb rate $LIMIT_RATE ceil $LIMIT_RATE

    # Фильтр: вся подсеть кроме админов → лимит
    EXCLUDE=$(build_admin_exclude)
    tc filter add dev $INTERFACE protocol ip parent 1: prio 1 u32 \
        match ip src $VPN_SUBNET $EXCLUDE flowid 1:10

    # ========== UPLOAD (от клиентов к серверу) ==========
    tc qdisc add dev $INTERFACE handle ffff: ingress
    tc filter add dev $INTERFACE parent ffff: protocol ip u32 match u32 0 0 \
        action mirred egress redirect dev ifb0

    tc qdisc add dev ifb0 root handle 1: htb default 10
    tc class add dev ifb0 parent 1: classid 1:1 htb rate 1000mbit
    tc class add dev ifb0 parent 1:1 classid 1:10 htb rate $LIMIT_RATE ceil $LIMIT_RATE

    tc filter add dev ifb0 protocol ip parent 1: prio 1 u32 \
        match ip dst $VPN_SUBNET $EXCLUDE flowid 1:10

    echo "Ограничение применено успешно!"
    echo "Обычные пользователи: ≤ $LIMIT_RATE"
    echo "Админы (${ADMIN_IPS[*]}): полная скорость"
}

remove_limits() {
    echo "Снимаю все ограничения скорости..."
    tc qdisc del dev $INTERFACE root 2>/dev/null || true
    tc qdisc del dev $INTERFACE ingress 2>/dev/null || true
    tc qdisc del dev ifb0 root 2>/dev/null || true
    ip link set ifb0 down 2>/dev/null || true
    ip link del ifb0 2>/dev/null || true
    echo "Все правила tc удалены."
}

install_autostart() {
    if ! crontab -l 2>/dev/null | grep -q "$0 apply"; then
        (crontab -l 2>/dev/null; echo "@reboot $(readlink -f $0) apply") | crontab -
        echo "Автозагрузка добавлена (crontab @reboot)."
    else
        echo "Автозагрузка уже настроена."
    fi
}

case "$1" in
    apply)
        apply_limits
        ;;
    remove)
        remove_limits
        ;;
    install)
        install_autostart
        ;;
    *)
        echo "Использование: $0 {apply|remove|install}"
        echo "  apply   — применить ограничение сейчас"
        echo "  remove  — снять все ограничения"
        echo "  install — добавить в автозагрузку"
        exit 1
        ;;
esac
