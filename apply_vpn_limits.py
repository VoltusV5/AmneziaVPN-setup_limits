#!/usr/bin/env python3

import subprocess
import os
import re

def parse_wg_conf(conf_path):
    peers = []
    with open(conf_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    current_peer = {}
    current_name = None

    for line in lines:
        line = line.strip()

        if line.startswith('#'):
            match = re.search(r'#\s*(Client:\s*)?(.+)', line, re.IGNORECASE)
            if match:
                current_name = match.group(2).strip()

        elif line == '[Peer]':
            if current_peer:
                peers.append(current_peer)
            current_peer = {'name': current_name}
            current_name = None

        elif '=' in line and current_peer:
            key, value = line.split('=', 1)
            current_peer[key.strip()] = value.strip()

    if current_peer:
        peers.append(current_peer)

    return peers

def is_unlimited(name):
    return name and 'VIP' in name.upper()

def setup_tc_egress_only(interface, peers, limit_rate='32mbit', total_rate='1000mbit'):
    """Ограничиваем только egress (upload от сервера к клиентам, т.е. download клиентов)."""
    # Очистка старых правил только на root (egress)
    subprocess.run(['tc', 'qdisc', 'del', 'dev', interface, 'root'], check=False)

    # HTB на egress
    subprocess.run(['tc', 'qdisc', 'add', 'dev', interface, 'root', 'handle', '1:', 'htb', 'default', '1'], check=True)
    subprocess.run(['tc', 'class', 'add', 'dev', interface, 'parent', '1:', 'classid', '1:1', 'htb', 'rate', total_rate, 'ceil', total_rate], check=True)

    class_id = 10
    for peer in peers:
        if 'AllowedIPs' not in peer:
            continue

        ip = peer['AllowedIPs'].split(',')[0].split('/')[0].strip()
        name = peer.get('name', '')

        if is_unlimited(name):
            continue  # VIP — без лимита

        # Класс с ограничением
        subprocess.run([
            'tc', 'class', 'add', 'dev', interface, 'parent', '1:1',
            'classid', f'1:{class_id}', 'htb', 'rate', limit_rate, 'ceil', limit_rate
        ], check=True)

        # Фильтр по dst IP (трафик к клиенту)
        subprocess.run([
            'tc', 'filter', 'add', 'dev', interface, 'parent', '1:',
            'protocol', 'ip', 'u32', 'match', 'ip', 'dst', ip,
            'flowid', f'1:{class_id}'
        ], check=True)

        class_id += 1

if __name__ == '__main__':
    conf_path = '/opt/amnezia/awg/wg0.conf'
    interface = 'wg0'

    if not os.path.exists(conf_path):
        print(f"ОШИБКА: Конфиг не найден: {conf_path}")
        exit(1)

    peers = parse_wg_conf(conf_path)
    print(f"Найдено {len(peers)} клиентов.")

    setup_tc_egress_only(interface, peers)

    subprocess.run(['wg', 'syncconf', interface, conf_path], check=True)

    print("Лимиты успешно применены!")
    print("• Только download клиентов ограничен (32 Мбит/с для non-VIP)")
    print("• Upload клиентов (их download) — без ограничений")
    print("• VIP-клиенты — полный безлимит")
