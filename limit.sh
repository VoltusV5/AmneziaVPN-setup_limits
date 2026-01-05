#!/bin/bash

# =====================================================
# Amnezia VPN — per-user лимит скорости 32 Мбит/с для обычных пользователей (OpenVPN подсеть)
# Админы на AmneziaWG (10.8.1.0/24) — полная скорость
# Простой и стабильный вариант без hash (для /24 работает)
# =====================================================

# ========== НАСТРОЙКИ ==========
LIMIT_RATE="32mbit"                  # скорость для каждого обычного пользователя

INTERFACE="eth0"                     # внешний интерфейс (проверь ip a, если не eth0 — измени)

VPN_SUBNET="10.8.0.0/24"             # подсеть обычных пользователей (OpenVPN over Cloak)
# =====================================================

set -e

apply_limits() {
    echo "Применяю per-user лимит $LIMIT_RATE на подсеть $VPN_SUBNET..."

    modprobe ifb || true
    ip link add ifb0 type ifb 2>/dev/null || true
    ip link set ifb0 up

    # Очистка всех правил
    tc qdisc del dev $INTERFACE root 2>/dev/null || true
    tc qdisc del dev $INTERFACE ingress 2>/dev/null || true
    tc qdisc del dev ifb0 root 2>/dev/null || true

    # === DOWNLOAD (с сервера к клиентам) ===
    tc qdisc add dev $INTERFACE root handle 1: htb default 9999
    tc class add dev $INTERFACE parent 1: classid 1:1 htb rate 1000mbit
    tc class add dev $INTERFACE parent 1:1 classid 1:10 htb rate $LIMIT_RATE ceil $LIMIT_RATE
    tc filter add dev $INTERFACE protocol ip parent 1: prio 1 u32 match ip src $VPN_SUBNET flowid 1:10

    # === UPLOAD (от клиентов к серверу) ===
    tc qdisc add dev $INTERFACE handle ffff: ingress
    tc filter add dev $INTERFACE parent ffff: protocol ip u32 match u32 0 0 action mirred egress redirect dev ifb0
    tc qdisc add dev ifb0 root handle 1: htb default 9999
    tc class add dev ifb0 parent 1: classid 1:1 htb rate 1000mbit
    tc class add dev ifb0 parent 1:1 classid 1:10 htb rate $LIMIT_RATE ceil $LIMIT_RATE
    tc filter add dev ifb0 protocol ip parent 1: prio 1 u32 match ip dst $VPN_SUBNET flowid 1:10

    echo "Лимит применён успешно!"
    echo "Каждый обычный пользователь: ≤ $LIMIT_RATE (независимо друг от друга)"
    echo "Админы (AmneziaWG): полная скорость"
}

remove_limits() {
    echo "Снимаю все ограничения..."
    tc qdisc del dev $INTERFACE root 2>/dev/null || true
    tc qdisc del dev $INTERFACE ingress 2>/dev/null || true
    tc qdisc del dev ifb0 root 2>/dev/null || true
    ip link set ifb0 down 2>/dev/null || true
    ip link del ifb0 2>/dev/null || true
    echo "Все правила удалены."
}

install_autostart() {
    local script_path=$(readlink -f "$0")
    if ! crontab -l 2>/dev/null | grep -q "$script_path apply"; then
        (crontab -l 2>/dev/null; echo "@reboot $script_path apply") | crontab -
        echo "Автозагрузка добавлена."
    else
        echo "Автозагрузка уже настроена."
    fi
}

case "$1" in
    apply) apply_limits ;;
    remove) remove_limits ;;
    install) install_autostart ;;
    *) echo "Использование: $0 {apply|remove|install}" ; exit 1 ;;
esac
