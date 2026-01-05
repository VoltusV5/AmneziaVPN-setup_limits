#!/usr/bin/env python3

import subprocess
import os
import re

def parse_wg_conf(conf_path):
    """Парсит wg0.conf, извлекает IP и имя клиента из комментариев."""
    peers = []
    with open(conf_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    current_peer = {}
    current_name = None

    for line in lines:
        line = line.strip()

        # Захватываем имя клиента из комментария
        if line.startswith('#'):
            match = re.search(r'#\s*(Client:\s*)?(.+)', line, re.IGNORECASE)
            if match:
                current_name = match.group(2).strip()

        elif line == '[Peer]':
            if current_peer:
                peers.append(current_peer)
            current_peer = {'name': current_name}
            current_name = None

        elif '=' in line and 'current_peer' in locals():
            key, value = line.split('=', 1)
            current_peer[key.strip()] = value.strip()

    if current_peer:
        peers.append(current_peer)

    return peers


def is_unlimited(name):
    """Если в имени клиента есть VIP (регистр не важен) — безлимит."""
    return name and 'VIP' in name.upper()


def setup_tc(interface, peers, limit_rate='32mbit', total_rate='1000mbit'):
    """Применяет ограничение скорости с помощью tc + HTB + IFB."""
    ifb = 'ifb0'

    # Очистка старых правил
    subprocess.run(['tc', 'qdisc', 'del', 'dev', interface, 'root'], check=False)
    subprocess.run(['tc', 'qdisc', 'del', 'dev', interface, 'ingress'], check=False)
    subprocess.run(['tc', 'qdisc', 'del', 'dev', ifb, 'root'], check=False)
    subprocess.run(['ip', 'link', 'del', 'dev', ifb], check=False)

    # Активируем IFB-модуль и интерфейс
    subprocess.run(['modprobe', 'ifb'], check=False)
    subprocess.run(['ip', 'link', 'add', 'name', ifb, 'type', 'ifb'], check=False)
    subprocess.run(['ip', 'link', 'set', 'dev', ifb, 'up'], check=True)

    # Ingress: перенаправляем входящий трафик на ifb0
    subprocess.run(['tc', 'qdisc', 'add', 'dev', interface, 'ingress', 'handle', 'ffff:', 'ingress'], check=True)
    subprocess.run([
        'tc', 'filter', 'add', 'dev', interface, 'parent', 'ffff:',
        'protocol', 'ip', 'u32', 'match', 'u32', '0', '0',
        'action', 'mirred', 'egress', 'redirect', 'dev', ifb
    ], check=True)

    # Egress (upload от сервера к клиенту)
    subprocess.run(['tc', 'qdisc', 'add', 'dev', interface, 'root', 'handle', '1:', 'htb', 'default', '1'], check=True)
    subprocess.run(['tc', 'class', 'add', 'dev', interface, 'parent', '1:', 'classid', '1:1', 'htb', 'rate', total_rate, 'ceil', total_rate], check=True)

    # Ingress на ifb0 (download от клиента к серверу)
    subprocess.run(['tc', 'qdisc', 'add', 'dev', ifb, 'root', 'handle', '1:', 'htb', 'default', '1'], check=True)
    subprocess.run(['tc', 'class', 'add', 'dev', ifb, 'parent', '1:', 'classid', '1:1', 'htb', 'rate', total_rate, 'ceil', total_rate], check=True)

    class_id = 10
    for peer in peers:
        if 'AllowedIPs' not in peer:
            continue

        # Берём первый IP (обычно x.x.x.x/32)
        ip = peer['AllowedIPs'].split(',')[0].split('/')[0].strip()
        name = peer.get('name', '')

        if is_unlimited(name):
            continue  # VIP — без ограничений

        # Ограничение upload (по dst IP)
        subprocess.run([
            'tc', 'class', 'add', 'dev', interface, 'parent', '1:1',
            'classid', f'1:{class_id}', 'htb', 'rate', limit_rate, 'ceil', limit_rate
        ], check=True)
        subprocess.run([
            'tc', 'filter', 'add', 'dev', interface, 'parent', '1:',
            'protocol', 'ip', 'u32', 'match', 'ip', 'dst', ip,
            'flowid', f'1:{class_id}'
        ], check=True)

        # Ограничение download (по src IP на ifb0)
        subprocess.run([
            'tc', 'class', 'add', 'dev', ifb, 'parent', '1:1',
            'classid', f'1:{class_id}', 'htb', 'rate', limit_rate, 'ceil', limit_rate
        ], check=True)
        subprocess.run([
            'tc', 'filter', 'add', 'dev', ifb, 'parent', '1:',
            'protocol', 'ip', 'u32', 'match', 'ip', 'src', ip,
            'flowid', f'1:{class_id}'
        ], check=True)

        class_id += 1


if __name__ == '__main__':
    conf_path = '/opt/amnezia/awg/wg0.conf'   # Путь внутри контейнера
    interface = 'wg0'

    if not os.path.exists(conf_path):
        print(f"ОШИБКА: Файл конфига не найден: {conf_path}")
        exit(1)

    peers = parse_wg_conf(conf_path)
    print(f"Найдено {len(peers)} клиентов.")

    setup_tc(interface, peers)

    # Применяем изменения WireGuard без рестарта
    subprocess.run(['wg', 'syncconf', interface, conf_path], check=True)

    print("Лимиты скорости успешно применены!")
    print("• Клиенты с VIP в имени — без ограничений")
    print("• Остальные — максимум 32 Мбит/с (upload + download)")
