#!/bin/bash

ADMIN_IPS=("10.8.1.1" "10.8.1.2")

LIMIT_RATE="32mbit"

INTERFACE="eth0"

VPN_SUBNET="10.8.0.0/24"


set -e


build_admin_exclude() {
    local exclude=""
    for ip in "${ADMIN_IPS[@]}"; do
        exclude="${exclude} match ip src not ${ip}/32"
        exclude="${exclude} match ip dst not ${ip}/32"
    done
    echo "$exclude"
}

apply_limits() {
    echo "Применяю ограничение скорости $LIMIT_RATE (кроме админов)..."


    modprobe ifb || true
    ip link add ifb0 type ifb 2>/dev/null || true
    ip link set ifb0 up


    tc qdisc del dev $INTERFACE root 2>/dev/null || true
    tc qdisc del dev $INTERFACE ingress 2>/dev/null || true
    tc qdisc del dev ifb0 root 2>/dev/null || true


    tc qdisc add dev $INTERFACE root handle 1: htb default 10
    tc class add dev $INTERFACE parent 1: classid 1:1 htb rate 1000mbit
    tc class add dev $INTERFACE parent 1:1 classid 1:10 htb rate $LIMIT_RATE ceil $LIMIT_RATE

    EXCLUDE=$(build_admin_exclude)
    tc filter add dev $INTERFACE protocol ip parent 1: prio 1 u32 \
        match ip src $VPN_SUBNET $EXCLUDE flowid 1:10


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
    local script_path=$(readlink -f "$0")
    if ! crontab -l 2>/dev/null | grep -q "$script_path apply"; then
        (crontab -l 2>/dev/null; echo "@reboot $script_path apply") | crontab -
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
