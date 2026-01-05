#!/bin/bash

# Упрощённый tc для OpenVPN in Amnezia — лимит 32 Мбит/с на download per-user
# Только egress (download для клиентов), без ifb (upload без лимита)
# Работает внутри контейнера amnezia-openvpn-cloak на tun0

DEV=tun0
RATE="32mbit"

case "$script_type" in
  up)
    tc qdisc add dev $DEV root handle 1: htb default 9999
    tc class add dev $DEV parent 1: classid 1:1 htb rate 1000mbit
    ;;

  client-connect)
    ip="$ifconfig_pool_remote_ip"
    if [ -n "$ip" ]; then
      # classid на основе последнего октета IP (например, для 10.8.0.5 — classid 1:10005)
      last_octet=$(echo $ip | awk -F. '{print $4}')
      classid=$((10000 + last_octet))
      tc class add dev $DEV parent 1:1 classid 1:$classid htb rate $RATE ceil $RATE
      tc filter add dev $DEV protocol ip parent 1: prio 1 u32 match ip dst $ip/32 flowid 1:$classid
    fi
    ;;

  client-disconnect)
    ip="$ifconfig_pool_remote_ip"
    if [ -n "$ip" ]; then
      last_octet=$(echo $ip | awk -F. '{print $4}')
      classid=$((10000 + last_octet))
      tc filter del dev $DEV protocol ip parent 1: prio 1 u32 match ip dst $ip/32 2>/dev/null || true
      tc class del dev $DEV classid 1:$classid 2>/dev/null || true
    fi
    ;;

  down)
    tc qdisc del dev $DEV root 2>/dev/null || true
    ;;
esac
