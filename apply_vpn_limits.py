#!/usr/bin/env python3

import subprocess
import os
import re

def get_unlimited_ips(unlimited_file):
    """Читает список безлимитных IP из файла (один на строку)."""
    ips = []
    if os.path.exists(unlimited_file):
        with open(unlimited_file, 'r') as f:
            for line in f:
                ip = line.strip()
                if ip:
                    ips.append(ip)
    return ips

def parse_wg_conf(conf_path):
    """Извлекает все AllowedIPs клиентов."""
    ips = []
    with open(conf_path, 'r', encoding='utf-8') as f:
        for line in f:
            if 'AllowedIPs' in line:
                ip = line.split('=')[1].strip().split('/')[0].split(',')[0].strip()
                ips.append(ip)
    return ips

def setup_tc_egress_only(interface, all_ips, unlimited_ips, limit_rate='32mbit', total_rate='1000mbit'):
    subprocess.run(['tc', 'qdisc', 'del', 'dev', interface, 'root'], check=False)

    subprocess.run(['tc', 'qdisc', 'add', 'dev', interface, 'root', 'handle', '1:', 'htb', 'default', '1'], check=True)
    subprocess.run(['tc', 'class', 'add', 'dev', interface, 'parent', '1:', 'classid', '1:1', 'htb',
                    'rate', total_rate, 'ceil', total_rate], check=True)

    class_id = 10
    for ip in all_ips:
        if ip in unlimited_ips:
            print(f"БЕЗЛИМИТ: {ip}")
            continue

        print(f"ОГРАНИЧЕН 32 Mbit/s: {ip}")

        subprocess.run([
            'tc', 'class', 'add', 'dev', interface, 'parent', '1:1',
            'classid', f'1:{class_id}', 'htb',
            'rate', limit_rate, 'ceil', limit_rate
        ], check=True)

        subprocess.run([
            'tc', 'filter', 'add', 'dev', interface, 'parent', '1:',
            'protocol', 'ip', 'u32', 'match', 'ip', 'dst', ip,
            'flowid', f'1:{class_id}'
        ], check=True)

        class_id += 1

if __name__ == '__main__':
    conf_path = '/opt/amnezia/awg/wg0.conf'
    unlimited_file = '/opt/amnezia/unlimited_ips.txt'  # Тот же файл, монтируется в контейнер
    interface = 'wg0'

    if not os.path.exists(conf_path):
        print(f"ОШИБКА: Конфиг не найден: {conf_path}")
        exit(1)

    all_ips = parse_wg_conf(conf_path)
    unlimited_ips = get_unlimited_ips(unlimited_file)

    print(f"Найдено клиентов: {len(all_ips)}")
    print(f"Безлимитных в файле: {len(unlimited_ips)}\n")

    setup_tc_egress_only(interface, all_ips, unlimited_ips)

    print("\nГотово! Лимиты применены по списку из файла.")
