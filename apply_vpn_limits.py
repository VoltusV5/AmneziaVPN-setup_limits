#!/usr/bin/env python3

import subprocess
import os
import re

def parse_wg_conf(conf_path):
    """Парсит wg0.conf и извлекает клиентов с их именами и AllowedIPs."""
    peers = []
    with open(conf_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    current_peer = {}
    current_name = None

    for line in lines:
        line = line.strip()

        # Ищем имя клиента в комментарии (поддерживаем разные форматы)
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

    # Добавляем последнего клиента, если есть
    if current_peer:
        peers.append(current_peer)

    return peers


def is_unlimited(name):
    """Возвращает True, если в имени клиента есть VIP (регистр не важен)."""
    return name is not None and 'VIP' in name.upper()


def setup_tc_egress_only(interface, peers, limit_rate='32mbit', total_rate='1000mbit'):
    """Ограничивает только исходящий трафик (download для клиентов)."""
    # Удаляем старые правила
    subprocess.run(['tc', 'qdisc', 'del', 'dev', interface, 'root'], check=False)

    # Создаём HTB на интерфейсе
    subprocess.run(['tc', 'qdisc', 'add', 'dev', interface, 'root', 'handle', '1:', 'htb', 'default', '1'], check=True)
    subprocess.run(['tc', 'class', 'add', 'dev', interface, 'parent', '1:', 'classid', '1:1', 'htb',
                    'rate', total_rate, 'ceil', total_rate], check=True)

    class_id = 10
    for peer in peers:
        if 'AllowedIPs' not in peer:
            continue

        # Берём основной IP клиента
        ip = peer['AllowedIPs'].split(',')[0].split('/')[0].strip()
        name = peer.get('name', '')

        if is_unlimited(name):
            print(f"Пропуск (безлимит): {name or 'Без имени'} → {ip}")
            continue

        print(f"Ограничение 32 Мбит/с: {name or 'Без имени'} → {ip}")

        # Создаём класс с ограничением
        subprocess.run([
            'tc', 'class', 'add', 'dev', interface, 'parent', '1:1',
            'classid', f'1:{class_id}', 'htb',
            'rate', limit_rate, 'ceil', limit_rate
        ], check=True)

        # Привязываем трафик к этому классу (по IP назначения)
        subprocess.run([
            'tc', 'filter', 'add', 'dev', interface, 'parent', '1:',
            'protocol', 'ip', 'u32', 'match', 'ip', 'dst', ip,
            'flowid', f'1:{class_id}'
        ], check=True)

        class_id += 1


if __name__ == '__main__':
    conf_path = '/opt/amnezia/awg/wg0.conf'   # Путь внутри контейнера
    interface = 'wg0'                         # Интерфейс внутри контейнера

    if not os.path.exists(conf_path):
        print(f"ОШИБКА: Конфиг не найден по пути {conf_path}")
        exit(1)

    peers = parse_wg_conf(conf_path)
    print(f"Найдено {len(peers)} клиентов.\n")

    setup_tc_egress_only(interface, peers)

    print("\nЛимиты скорости успешно применены!")
    print("• Обычные пользователи: максимум 32 Мбит/с на скачивание (download)")
    print("• Пользователи с VIP в имени: полный безлимит")
    print("• Upload клиентов (их скачивание на сервер): не ограничен из-за особенностей Docker")
