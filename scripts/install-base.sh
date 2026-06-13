#!/usr/bin/env bash
# klipper-kiln — base install for Raspberry Pi OS Lite (Trixie, 64-bit)
# on a Pi Zero 2 W.  Installs Klipper + Moonraker + Mainsail under a
# dedicated `klipper` service account.
#
# Run as a sudo-capable login user (e.g. `kelchm`) with passwordless sudo:
#   ssh duncan0 'bash -s' < scripts/install-base.sh
#
# Idempotent: safe to re-run; existing artifacts are left alone.

set -euo pipefail

KU=klipper            # service account name
KH=/home/$KU          # service account home

log()        { echo; echo "###### $*"; }
as_klipper() { sudo -u $KU -H "$@"; }

#======================================================================#
# 1) System-wide setup (apt + service user creation)                    #
#======================================================================#

log "apt update + upgrade + base deps"
sudo DEBIAN_FRONTEND=noninteractive apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" full-upgrade
sudo DEBIAN_FRONTEND=noninteractive apt-get -y install \
    git python3 python3-venv python3-pip python3-dev build-essential \
    libffi-dev libncurses-dev libusb-1.0-0-dev pkg-config \
    stm32flash gcc-arm-none-eabi binutils-arm-none-eabi libnewlib-arm-none-eabi \
    dfu-util nginx unzip curl wget

log "Create service account '$KU'"
if ! id $KU >/dev/null 2>&1; then
    sudo useradd --system --create-home --home-dir $KH --shell /bin/bash $KU
fi
# Groups required for serial (dialout), Pi SPI/I2C/GPIO, hub/USB hotplug
sudo usermod -aG dialout,tty,spi,gpio,i2c,plugdev $KU || true
# Make home traversable so the admin user can inspect klipper's files
# (default `useradd --system` gives 0700; we want at least 0755 for `x` access)
sudo chmod 755 $KH
echo "klipper user is in groups: $(id $KU)"

#======================================================================#
# 2) klipper user: clone, venv, pre-build c_helper.so                   #
#======================================================================#

log "Clone Klipper + Moonraker into $KH"
as_klipper bash -c "[[ -d $KH/klipper ]]   || git clone --depth=1 https://github.com/Klipper3d/klipper.git $KH/klipper"
as_klipper bash -c "[[ -d $KH/moonraker ]] || git clone --depth=1 https://github.com/Arksine/moonraker.git $KH/moonraker"

log "Klippy python venv + requirements"
as_klipper bash -c "[[ -d $KH/klippy-env ]] || python3 -m venv $KH/klippy-env"
as_klipper $KH/klippy-env/bin/pip install --upgrade pip wheel setuptools
as_klipper $KH/klippy-env/bin/pip install -r $KH/klipper/scripts/klippy-requirements.txt

log "Pre-build c_helper.so (prevents OOM on klipper start)"
as_klipper bash -c "cd $KH/klipper/klippy/chelper && $KH/klippy-env/bin/python -c 'import sys; sys.path.insert(0, \"..\"); from chelper import get_ffi; get_ffi(); print(\"c_helper.so built OK\")'"

log "Install gcode_shell_command extension (used by network.cfg for WiFi toggle)"
as_klipper curl -sSfL -o $KH/klipper/klippy/extras/gcode_shell_command.py \
    https://raw.githubusercontent.com/DangerKlippers/danger-klipper/master/klippy/extras/gcode_shell_command.py

# Note: /etc/sudoers.d/099-klipper-nmcli must be created manually after install
# with the actual home-WiFi connection name. Example:
#   echo "klipper ALL=(ALL) NOPASSWD: /usr/bin/nmcli connection up kiln-ap, /usr/bin/nmcli connection up <HOME_WIFI_NAME>" \
#     | sudo tee /etc/sudoers.d/099-klipper-nmcli
#   sudo chmod 440 /etc/sudoers.d/099-klipper-nmcli

log "kiln_data directory layout"
as_klipper mkdir -p $KH/kiln_data/{config,logs,gcodes,comms,systemd,backup,database,certs}

log "Stub kiln.cfg (overwritten later when real configs are deployed)"
as_klipper bash -c "[[ -f $KH/kiln_data/config/kiln.cfg ]] || cat > $KH/kiln_data/config/kiln.cfg" <<'CFG'
# Kiln controller — base stub. Replace with the deployed config tree.
[mcu]
serial: /dev/null
[printer]
kinematics: none
max_velocity: 1
max_accel: 1
[virtual_sdcard]
path: ~/kiln_data/gcodes
[display_status]
[pause_resume]
CFG

#======================================================================#
# 3) klipper.service (Restart=on-failure + StartLimit safety)           #
#======================================================================#

log "klipper.service systemd unit"
sudo tee $KH/kiln_data/systemd/klipper.env >/dev/null <<ENV
KLIPPER_ARGS="$KH/klipper/klippy/klippy.py $KH/kiln_data/config/kiln.cfg -I $KH/kiln_data/comms/klippy.serial -l $KH/kiln_data/logs/klippy.log -a $KH/kiln_data/comms/klippy.sock"
ENV
sudo chown $KU:$KU $KH/kiln_data/systemd/klipper.env

sudo tee /etc/systemd/system/klipper.service >/dev/null <<UNIT
[Unit]
Description=Klipper 3D Printer Firmware
Documentation=https://www.klipper3d.org/
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=600
StartLimitBurst=3

[Install]
WantedBy=multi-user.target

[Service]
Type=simple
User=$KU
Group=$KU
RemainAfterExit=yes
WorkingDirectory=$KH/klipper
EnvironmentFile=$KH/kiln_data/systemd/klipper.env
ExecStart=$KH/klippy-env/bin/python \$KLIPPER_ARGS
Restart=on-failure
RestartSec=10
UNIT
sudo systemctl daemon-reload
sudo systemctl enable klipper
# Do NOT start klipper yet — finish moonraker + mainsail first to avoid
# competing for memory on the Zero 2 W.

#======================================================================#
# 4) Moonraker installer (must run as $KU; needs sudo temporarily)      #
#======================================================================#

log "Grant temporary NOPASSWD sudo to '$KU' for moonraker installer"
echo "$KU ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/099-klipper-install >/dev/null
sudo chmod 440 /etc/sudoers.d/099-klipper-install

log "Run install-moonraker.sh as $KU"
sudo -u $KU -H bash -c "$KH/moonraker/scripts/install-moonraker.sh -f -s"

log "Revoke temporary sudo grant"
sudo rm -f /etc/sudoers.d/099-klipper-install

log "Moonraker config: UDS path + authorization + update_manager"
as_klipper sed -i "s|^klippy_uds_address:.*|klippy_uds_address: $KH/kiln_data/comms/klippy.sock|" $KH/kiln_data/config/moonraker.conf
if ! sudo -u $KU grep -q '^\[authorization\]' $KH/kiln_data/config/moonraker.conf; then
    sudo -u $KU bash -c "cat >> $KH/kiln_data/config/moonraker.conf" <<'MR'

[authorization]
force_logins: False
cors_domains:
    *.local
    *.lan
    *://localhost
    *://localhost:*
    *://app.fluidd.xyz
    *://my.mainsail.xyz
trusted_clients:
    10.0.0.0/8
    127.0.0.0/8
    169.254.0.0/16
    172.16.0.0/12
    192.168.0.0/16
    FE80::/10
    ::1/128
[file_manager]
enable_object_processing: False
[history]
[octoprint_compat]
[update_manager]
refresh_interval: 168
enable_auto_refresh: True
[update_manager mainsail]
type: web
channel: stable
repo: mainsail-crew/mainsail
path: /var/www/mainsail
MR
fi
sudo systemctl restart moonraker

#======================================================================#
# 5) Mainsail static deploy + nginx                                     #
#======================================================================#

log "Mainsail static deploy"
sudo mkdir -p /var/www/mainsail
cd /tmp && rm -f mainsail.zip
wget -q https://github.com/mainsail-crew/mainsail/releases/latest/download/mainsail.zip
sudo unzip -o -q mainsail.zip -d /var/www/mainsail
sudo chown -R www-data:www-data /var/www/mainsail

log "nginx site for Mainsail"
sudo tee /etc/nginx/sites-available/mainsail >/dev/null <<'NGINX'
upstream apiserver { server 127.0.0.1:7125; }

server {
    listen 80 default_server;
    listen [::]:80 default_server;
    access_log /var/log/nginx/mainsail-access.log;
    error_log /var/log/nginx/mainsail-error.log;
    root /var/www/mainsail;
    index index.html;
    server_name _;
    client_max_body_size 0;
    proxy_request_buffering off;

    location / { try_files $uri $uri/ /index.html; }
    location = /index.html { add_header Cache-Control "no-store, no-cache, must-revalidate"; }

    location /websocket {
        proxy_pass http://apiserver/websocket;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $http_connection;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Scheme $scheme;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 86400;
    }
    location ~ ^/(printer|api|access|machine|server)/ {
        proxy_pass http://apiserver$request_uri;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $http_connection;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Scheme $scheme;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
NGINX
sudo rm -f /etc/nginx/sites-enabled/default
sudo ln -sf /etc/nginx/sites-available/mainsail /etc/nginx/sites-enabled/mainsail
sudo nginx -t
sudo systemctl restart nginx
sudo systemctl enable nginx

#======================================================================#
# 6) Pi hardware SPI (MAX31856 host lives here later)                   #
#======================================================================#

log "Enable SPI with no kernel-managed CS (frees BCM 7/8 as GPIOs for MAX31856 CS)"
# Replace `dtparam=spi=on` (which reserves CE0/CE1) with spi0-0cs overlay.
if grep -q '^dtparam=spi=on' /boot/firmware/config.txt; then
    sudo sed -i 's|^dtparam=spi=on|dtoverlay=spi0-0cs|' /boot/firmware/config.txt
elif ! grep -q '^dtoverlay=spi0-0cs' /boot/firmware/config.txt; then
    sudo raspi-config nonint do_spi 0
    sudo sed -i 's|^dtparam=spi=on|dtoverlay=spi0-0cs|' /boot/firmware/config.txt
fi

log "Switch USB controller from legacy dwc_otg to dwc2 (root cause of urb_dequeue wedges)"
# The image ships dwc2 only in [cm5] section. Pi Zero 2 W needs it in [all] too.
if ! grep -q '^dtoverlay=dwc2' /boot/firmware/config.txt; then
    echo 'dtoverlay=dwc2,dr_mode=host' | sudo tee -a /boot/firmware/config.txt >/dev/null
fi

log "Disable WiFi power-save (Pi Zero 2 W brcmfmac default is ON → 50-100ms SSH typing latency)"
WIFI_CONN=$(nmcli -t -f NAME,TYPE connection show --active | awk -F: '$2=="802-11-wireless"{print $1; exit}')
if [[ -n "$WIFI_CONN" ]]; then
    sudo nmcli connection modify "$WIFI_CONN" 802-11-wireless.powersave 2
    sudo nmcli connection up "$WIFI_CONN" >/dev/null 2>&1 || true
    echo "powersave disabled on: $WIFI_CONN"
fi

#======================================================================#
# 7) Start klipper LAST                                                 #
#======================================================================#

log "Start klipper (c_helper.so already built)"
sudo systemctl start klipper

sleep 8
log "Final state"
for svc in klipper moonraker nginx; do
    printf "%-12s enabled=%s active=%s\n" "$svc" \
        "$(systemctl is-enabled $svc 2>&1)" \
        "$(systemctl is-active $svc 2>&1)"
done
echo
free -h
echo
echo "Mainsail: http://duncan0/   (or http://10.32.99.70/)"
