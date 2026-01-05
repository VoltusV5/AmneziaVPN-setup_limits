#!/bin/bash

# =====================================================
# Amnezia VPN — ограничение скорости 32 Мбит/с per-user для обычных (OpenVPN подсеть)
# Админы на AmneziaWG (10.8.1.0/24) — полная скорость автоматически
# Используем hash-table для правильного матча подсети
# =====================================================

# ========== НАСТРОЙКИ ==========
LIMIT_RATE="32mbit"                  # скорость для каждого обычного пользователя

INTERFACE="eth0"                     # внешний интерфейс (если не eth0 — измени после ip a)

VPN_SUBNET="10.8.0.0/24"             # подсеть обычных (OpenVPN over Cloak)
# =====================================================

set -e

apply_limits() {
    echo "Применяю per-user лимит $LIMIT_RATE на подсеть $VPN_SUBNET..."

    modprobe ifb || true
    ip link add ifb0 type ifb 2>/dev/null || true
    ip link set ifb0 up

    # Очистка
    tc qdisc del dev $INTERFACE root 2>/dev/null || true
    tc qdisc del dev $INTERFACE ingress 2>/dev/null || true
    tc qdisc del dev ifb0 root 2>/dev/null || true

    # Создаём hash-table для подсети (divisor 256 — достаточно для /24)
    tc filter add dev $INTERFACE parent ffff: protocol ip u32 divisor 256
    tc filter add dev $INTERFACE protocol ip parent 1: prio 1 u32 \
        ht 800:: \
        match ip src $VPN_SUBNET \
        hashkey mask 0x000000ff at 16 \
        link 1::

    # DOWNLOAD
    tc qdisc add dev $INTERFACE root handle 1: htb default 9999
    tc class add dev $INTERFACE parent 1: classid 1:1 htb rate 1000mbit
    tc class add dev $INTERFACE parent 1:1 classid 1:10 htb rate $LIMIT_RATE ceil $LIMIT_RATE prio 1
    tc filter add dev $INTERFACE protocol ip parent 1: prio 1 handle 1: u32 flowid 1:10

    # UPLOAD
    tc qdisc add dev $INTERFACE handle ffff: ingress
    tc filter add dev $INTERFACE parent ffff: protocol ip u32 match u32 0 0 action mirred egress redirect dev ifb0
    tc qdisc add dev ifb0 root handle 2: htb default 9999
    tc class add dev ifb0 parent 2: classid 2:1 htb rate 1000mbit
    tc class add dev ifb0 parent 2:1 classid 2:10 htb rate $LIMIT_RATE ceil $LIMIT_RATE prio 1
    tc filter add dev ifb0 protocol ip parent 2: prio 1 handle 1: u32 flowid 2:10

    echo "Лимит применён успешно! Каждый обычный пользователь — ≤ $LIMIT_RATE независимо."
    echo "Админы (AmneziaWG): полная скорость."
}

remove_limits() {
    echo "Снимаю лимит..."
    tc qdisc del dev $INTERFACE root 2>/dev/null || true
    tc qdisc del dev $INTERFACE ingress 2>/dev/null || true
    tc qdisc del dev ifb0 root 2>/dev/null || true
    ip link set ifb0 down 2>/dev/null || true
    ip link del ifb0 2>/dev/null || true
    echo "Правила удалены."
}

install_autostart() {
    local script_path=$(readlink -f "$0")
    if ! crontab -l 2>/dev/null | grep -q "$script_path apply"; then
        (crontab -l 2>/dev/null; echo "@reboot $script_path apply") | crontab -
        echo "Автозагрузка добавлена."
    fi
}

case "$1" in
    apply) apply_limits ;;
    remove) remove_limits ;;
    install) install_autostart ;;
    *) echo "Использование: $0 {apply|remove|install}" ; exit 1 ;;
esac
