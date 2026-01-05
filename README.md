# AmneziaVPN Speed Limits Setup (MVP)

Этот README описывает настройку ограничения скорости для пользователей Amnezia VPN (AmneziaWG в Docker-контейнере `amnezia-awg`).

- Обычные пользователи — максимум **32 Мбит/с** на скачивание (download).
- Безлимитные пользователи — полный канал (определяются по IP в отдельном файле).

## Установка и настройка (один раз)

1. **Установите python-скрипт в контейнер**  
   (он считывает список безлимитных IP и применяет лимиты)

   ```bash
   sudo wget https://raw.githubusercontent.com/VoltusV5/AmneziaVPN-setup_limits/main/apply_vpn_limits_by_file.py -O /usr/local/bin/apply_vpn_limits_by_file.py
   sudo docker cp /usr/local/bin/apply_vpn_limits_by_file.py amnezia-awg:/usr/local/bin/apply_vpn_limits.py
   ```

2. **Создайте файл для списка безлимитных IP внутри контейнера**

   ```bash
   sudo docker exec amnezia-awg touch /opt/amnezia/unlimited_ips.txt
   sudo docker exec amnezia-awg chmod 644 /opt/amnezia/unlimited_ips.txt
   ```

3. **Установите bash-скрипт на хост**  
   (для добавления последнего пользователя в безлимитные)

   ```bash
   sudo wget -O /usr/local/bin/add_vip.sh https://raw.githubusercontent.com/VoltusV5/AmneziaVPN-setup_limits/main/add_vip.sh
   sudo chmod +x /usr/local/bin/add_vip.sh
   ```

## Как добавлять пользователей

1. **Обычный пользователь (с лимитом 32 Мбит/с)**  
   - Создаёте пользователя через Amnezia VPN client (как обычно).  
   - Отправляете ему config-файл.  
   - **Ничего больше не запускаете** — лимит 32 Мбит/с на download применится автоматически при следующем запуске python-скрипта (вручную или через монитор, если он настроен).

2. **Безлимитный пользователь**  
   - Создаёте пользователя через Amnezia VPN client.  
   - После создания запускаете **одну** команду:

     ```bash
     sudo /usr/local/bin/add_vip.sh
     ```

   Скрипт сам найдёт IP последнего пользователя, добавит его в список безлимитных и сразу применит лимиты.

## Проверка и полезные команды

- Посмотреть текущие безлимитные IP:
  ```bash
  sudo docker exec amnezia-awg cat /opt/amnezia/unlimited_ips.txt
  ```

- Вручную применить лимиты ко всем пользователям:
  ```bash
  sudo docker exec amnezia-awg python3 /usr/local/bin/apply_vpn_limits.py
  ```

- Проверить, что правила tc активны:
  ```bash
  sudo docker exec amnezia-awg tc qdisc show dev wg0
  sudo docker exec amnezia-awg tc class show dev wg0
  ```
