#!/bin/bash

# =====================================================
# Amnezia VPN — лимит скорости 32 Мбит/с на DOWNLOAD для обычных пользователей (OpenVPN подсеть 10.8.0.0/24)
# Админы на AmneziaWG (10.8.1.0/24) — полная скорость автоматически
# Только egress shaping (download для клиентов) — без ingress (чтобы избежать ошибок)
# =====================================================

# ========== НАСТРОЙКИ ==========
LIMIT_RATE="32mbit"                  # скорость download для каждого обычного пользователя

INTERFACE="eth0"                     # внешный интерфейс (если не eth0 — проверь ip a и измени)
# =====================================================

set -e

apply_limits() {
    echo "Применяю лимит $LIMIT_RATE на download для обычных пользователей..."

    # Очистка
    tc qdisc del dev $INTERFACE root 2>/dev/null || true

    # HTB для egress (download для клиентов = upload с сервера)
    tc qdisc add dev $INTERFACE root handle 1: htb default 9999
    tc class add dev $INTERFACE parent 1: classid 1:1 htb rate 1000mbit
    tc class add dev $INTERFACE parent 1:1 classid 1:10 htb rate $LIMIT_RATE ceil $LIMIT_RATE

    # Фильтр на всю подсеть OpenVPN (per-user автоматически через HTB)
    tc filter add dev $INTERFACE protocol ip parent 1: prio 1 u32 match ip src 10.8.0.0/24 flowid 1:10

    echo "Лимит на download применён успешно!"
    echo "Каждый обычный пользователь: ≤ $LIMIT_RATE на download"
    echo "Upload — без лимита (полная скорость)"
    echo "Админы (AmneziaWG): полная скорость в обе стороны"
}

remove_limits() {
    echo "Снимаю лимит..."
    tc qdisc del dev $INTERFACE root 2>/dev/null || true
    echo "Правила удалены."
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
