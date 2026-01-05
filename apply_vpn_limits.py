import subprocess
import os
import re

def parse_wg_conf(conf_path):
    peers = []
    with open(conf_path, 'r') as f:
        lines = f.readlines()
    current_peer = {}
    current_name = None
    for line in lines:
        line = line.strip()
        if line.startswith('#'):
            # Захватываем комментарий как имя (например, # Client: VIP_my_pc или # VIP_my_pc)
            match = re.search(r'#\s*(Client:\s*)?(.+)', line)
            if match:
                current_name = match.group(2).strip()
        elif line == '[Peer]':
            if current_peer:
                peers.append(current_peer)
            current_peer = {'name': current_name}
            current_name = None  # Сбрасываем после использования
        elif '=' in line:
            key, value = line.split('=', 1)
            current_peer[key.strip()] = value.strip()
    if current_peer:
        peers.append(current_peer)
    return peers

def is_unlimited(name):
    return name and 'VIP' in name.upper()

def setup_tc(interface, peers, limit_rate='32mbit', total_rate='1000mbit'):
    # Очистка существующих правил
    subprocess.run(['tc', 'qdisc', 'del', 'dev', interface, 'root'], check=False)
    subprocess.run(['tc', 'qdisc', 'del', 'dev', interface, 'ingress'], check=False)

    # Настройка IFB для ingress (download limit)
    ifb = 'ifb0'
    subprocess.run(['modprobe', 'ifb'], check=False)
    subprocess.run(['ip', 'link', 'add', ifb, 'type', 'ifb'], check=False)
    subprocess.run(['ip', 'link', 'set', ifb, 'up'], check=False)

    # Перенаправление ingress на IFB
    subprocess.run(['tc', 'qdisc', 'add', 'dev', interface, 'ingress', 'handle', 'ffff:'], check=True)
    subprocess.run(['tc', 'filter', 'add', 'dev', interface, 'parent', 'ffff:', 'protocol', 'ip', 'u32', 'match', 'u32', '0', '0', 'action', 'mirred', 'egress', 'redirect', 'dev', ifb], check=True)

    # Egress (upload limit)
    subprocess.run(['tc', 'qdisc', 'add', 'dev', interface, 'root', 'handle', '1:', 'htb', 'default', '1'], check=True)
    subprocess.run(['tc', 'class', 'add', 'dev', interface, 'parent', '1:', 'classid', '1:1', 'htb', 'rate', total_rate, 'ceil', total_rate], check=True)

    # Ingress on IFB (download limit)
    subprocess.run(['tc', 'qdisc', 'add', 'dev', ifb, 'root', 'handle', '1:', 'htb', 'default', '1'], check=True)
    subprocess.run(['tc', 'class', 'add', 'dev', ifb, 'parent', '1:', 'classid', '1:1', 'htb', 'rate', total_rate, 'ceil', total_rate], check=True)

    class_id = 10
    for peer in peers:
        if 'AllowedIPs' in peer:
            ip = peer['AllowedIPs'].split('/')[0]  # Берем IP (assume /32)
            name = peer.get('name', '')
            if not is_unlimited(name):
                # Egress: limit by dst IP
                subprocess.run(['tc', 'class', 'add', 'dev', interface, 'parent', '1:1', 'classid', f'1:{class_id}', 'htb', 'rate', limit_rate, 'ceil', limit_rate], check=True)
                subprocess.run(['tc', 'filter', 'add', 'dev', interface, 'parent', '1:', 'protocol', 'ip', 'u32', 'match', 'ip', 'dst', ip, 'flowid', f'1:{class_id}'], check=True)

                # Ingress: limit by src IP
                subprocess.run(['tc', 'class', 'add', 'dev', ifb, 'parent', '1:1', 'classid', f'1:{class_id}', 'htb', 'rate', limit_rate, 'ceil', limit_rate], check=True)
                subprocess.run(['tc', 'filter', 'add', 'dev', ifb, 'parent', '1:', 'protocol', 'ip', 'u32', 'match', 'ip', 'src', ip, 'flowid', f'1:{class_id}'], check=True)

                class_id += 1

if __name__ == '__main__':
    conf_path = '/opt/amnezia/awg/wg0.conf'  # Измени на свой точный путь после поиска
    interface = 'wg0'  # Интерфейс WireGuard
    peers = parse_wg_conf(conf_path)
    setup_tc(interface, peers)
    # Применяем изменения в WireGuard без рестарта
    subprocess.run(['wg', 'syncconf', interface, conf_path], check=True)
