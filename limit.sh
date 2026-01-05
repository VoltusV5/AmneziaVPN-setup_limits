#!/bin/bash

# =====================================================
# Amnezia VPN — лимит 32 Мбит/с на DOWNLOAD для обычных пользователей (OpenVPN подсеть 10.8.0.0/24)
# Админы на AmneziaWG (10.8.1.0/24) — полная скорость автоматически
# Используем iptables mark + tc fw filter (работает на всех версиях tc)
# =====================================================

# ========== НАСТРОЙКИ ==========
LIMIT_RATE="32mbit"                  # скорость download для каждого обычного пользователя

INTERFACE="eth0"                     # внешний интерфейс
VPN_SUBNET="10.8.0.0/24"             # подсеть обычных (OpenVPN over Cloak)
MARK=10                              # марка для iptables
# =====================================================

set -e

apply_limits() {
    echo "Применяю лимит $LIMIT_RATE на download для подсети $VPN_SUBNET (через iptables + tc fw)..."

    # Очистка старых правил
    tc qdisc del dev $INTERFACE root 2>/dev/null || true
    iptables -t mangle -D OUTPUT -s $VPN_SUBNET -j MARK --set-mark $MARK 2>/dev/null || true

    # Маркируем трафик из VPN-подсети (upload с сервера = download для клиентов)
    iptables -t mangle -A OUTPUT -s $VPN_SUBNET -j MARK --set-mark $MARK

    # HTB на egress
    tc qdisc add dev $INTERFACE root handle 1: htb default 9999
    tc class add dev $INTERFACE parent 1: classid 1:1 htb rate 1000mbit
    tc class add dev $INTERFACE parent 1:1 classid 1:10 htb rate $LIMIT_RATE ceil $LIMIT_RATE

    # Фильтр по марке (fw)
    tc filter add dev $INTERFACE protocol ip parent 1: prio 1 handle $MARK fw flowid 1:10

    echo "Лимит применён успешно!"
    echo "Каждый обычный пользователь: ≤ $LIMIT_RATE на download"
    echo "Upload — без лимита"
    echo "Админы (AmneziaWG): полная скорость"
}

remove_limits() {
    echo "Снимаю лимит..."
    tc qdisc del dev $INTERFACE root 2>/dev/null || true
    iptables -t mangle -D OUTPUT -s $VPN_SUBNET -j MARK --set-mark $MARK 2>/dev/null || true
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
