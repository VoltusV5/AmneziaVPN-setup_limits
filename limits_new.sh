#!/bin/bash

# Упрощённый tc для OpenVPN in Amnezia — лимит 32 Мбит/с на download per-user
# С логом в /tmp/tc.log для дебага

DEV=tun0
RATE="32mbit"
LOG="/tmp/tc.log"

echo "$(date) script_type=$script_type ip=$ifconfig_pool_remote_ip cn=$common_name" >> $LOG

case "$script_type" in
  up)
    echo "$(date) UP: создаю root htb на $DEV" >> $LOG
    tc qdisc del dev $DEV root 2>/dev/null || true
    tc qdisc add dev $DEV root handle 1: htb default 9999
    tc class add dev $DEV parent 1: classid 1:1 htb rate 1000mbit
    echo "$(date) UP: root htb создан" >> $LOG
    ;;

  client-connect)
    ip="$ifconfig_pool_remote_ip"
    if [ -n "$ip" ]; then
      echo "$(date) CONNECT: клиент $cn с IP $ip" >> $LOG
      last_octet=$(echo $ip | awk -F. '{print $4}')
      classid=$((10000 + last_octet))
      tc class add dev $DEV parent 1:1 classid 1:$classid htb rate $RATE ceil $RATE
      tc filter add dev $DEV protocol ip parent 1: prio 1 u32 match ip dst $ip/32 flowid 1:$classid
      echo "$(date) CONNECT: класс 1:$classid создан с rate $RATE для $ip" >> $LOG
    else
      echo "$(date) CONNECT: ошибка — нет IP" >> $LOG
    fi
    ;;

  client-disconnect)
    ip="$ifconfig_pool_remote_ip"
    if [ -n "$ip" ]; then
      echo "$(date) DISCONNECT: клиент $cn с IP $ip" >> $LOG
      last_octet=$(echo $ip | awk -F. '{print $4}')
      classid=$((10000 + last_octet))
      tc filter del dev $DEV protocol ip parent 1: prio 1 u32 match ip dst $ip/32 2>/dev/null || true
      tc class del dev $DEV classid 1:$classid 2>/dev/null || true
      echo "$(date) DISCONNECT: класс 1:$classid удалён" >> $LOG
    fi
    ;;

  down)
    echo "$(date) DOWN: удаляю root htb" >> $LOG
    tc qdisc del dev $DEV root 2>/dev/null || true
    ;;
esac
