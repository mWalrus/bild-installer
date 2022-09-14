#!/usr/bin/env bash

# Colors
RED="\e[91m"
GREEN="\e[92m"
YELLOW="\e[93m"
BLUE="\e[94m"
MAGENTA="\e[95m"
BLACK="\e[30m"
B="\e[1m"
R="\e[0m"

function green_bold() {
  echo -e "${GREEN}${B}[Bild Install] $1${R}"
}

function new_task() {
  echo -e "${BLUE}${B}[Bild Install] ->${R} $1"
}

function info() {
  echo -e "${MAGENTA}${B}[Bild Install] ..${R} $1"
}

function bold() {
  echo -e "${B}$1${R}"
}

function warn() {
  echo -e "${YELLOW}${B}[Bild Install] !! $1${R}"
}

function list() {
  while (( "$#" )); do
    echo -e "${MAGENTA}${B} - ${R}$1"
    shift
  done
}

function read_string() {
  echo $(read -p "$(echo -e "${BLUE}${B}[Bild Install] $1:${R} ")" RES; echo $RES)
}

function confirm() {
  if $2; then
    YN="[Y/n]"
  else
    YN="[y/N]"
  fi
  
  read -p "$1 $YN " REPLY
  REPLY=$REPLY | awk '{print tolower($0)}'
  if [ "$REPLY" == "n" ] || [ "$REPLY" == "no" ]; then
    false
  elif [ ! $2 ] && [ "$REPLY" == "" ]; then
    false
  else
    true
  fi
}

green_bold "Welcome to the bild installer!"

# Retrieve the distro name
DISTRO=$(cat /etc/*-release | grep DISTRIB_ID | awk -F"=" '{print $2}') | sed 's/"//'

# If distro is not ubuntu, warn the user of risk
if [ "$DISTRO" != "Ubuntu" ]; then
  warn "It looks like you're not running Ubuntu"
  CONTINUE=$(confirm "Things might not work as intended, continue anyways?" false)
  if ! $CONTINUE ; then
    green_bold "Exiting"
    exit 0
  fi
fi


new_task "Installing required packages:"
list "nginx" "certbot" "python3-certbot-nginx" "gcc"
apt install nginx certbot python3-certbot-nginx gcc

new_task "Making sure nginx is up and running"
systemctl start nginx && systemctl enable nginx

new_task "Installing rustup"
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

info "Adding cargo binaries to PATH"
source "$HOME/.cargo/env"

info "Installing rustup nightly toolchain"
rustup install nightly

DOMAIN_NAME="i.$(read_string "Enter your domain name (ex: your-domain.com)")"

new_task "Creating nginx config file"
NGINX_CONF_FILE="/etc/nginx/sites-available/$DOMAIN_NAME.conf"
if [ -f "$NGINX_CONF_FILE" ]; then
  info "Looks like $NGINX_CONF_FILE already exists"
  if [ grep -q "server_name $DOMAIN_NAME www.$DOMAIN_NAME" ]; then
    info "Updating conf file with required fields"
    sed "/server_name $DOMAIN_NAME www.$DOMAIN_NAME/a \tlocation / {\n\t\tproxy_pass http://127.0.0.1:1337;\n\t}" $NGINX_CONF_FILE
  fi
else
  touch "$NGINX_CONF_FILE"
  echo "server {" >> $NGINX_CONF_FILE
  echo "  server_name $DOMAIN_NAME www.$DOMAIN_NAME;" >> $NGINX_CONF_FILE
  echo "  location / {" >> $NGINX_CONF_FILE
  echo "    proxy_pass http://127.0.0.1:1337;" >> $NGINX_CONF_FILE
  echo "  }" >> $NGINX_CONF_FILE
  echo "}" >> $NGINX_CONF_FILE
  
  info "Wrote server configuration to $(bold $NGINX_CONF_FILE)"
fi

info "Symlinking $(bold $NGINX_CONF_FILE) to $(bold "/etc/nginx/sites-enabled/$DOMAIN_NAME.conf")"
ln -s $NGINX_CONF_FILE /etc/nginx/sites-enabled/$DOMAIN_NAME.conf

new_task "Start certificate generation with certbot"
if $(confirm "Do you want to generate certificates with certbot?" true); then
  info "Generating certs"
  certbot --nginx

  info "Reloading nginx"
  systemctl reload nginx
else
  info "Skipping cert generation"
fi


new_task "Cloning down bild repo to $(bold "/var/www/bild")"
git clone https://gitlab.com/mWalrus/bild.git /var/www/bild

info "Changing $(bold "/var/www/bild")'s owner to www-data"
chown -R www-data: /var/www/bild

new_task "Compiling project binaries"
cd /var/www/bild && rustup run nightly cargo build --release

new_task "Adding systemd service $(bold /etc/systemd/system/bild-server.service)"
echo "
[Unit]
Description=My Rocket application for your-domain.com

[Service]
User=www-data
Group=www-data
# The user www-data should probably own that directory
WorkingDirectory=/var/www/bild
Environment=\"ROCKET_ENV=prod\"
Environment=\"ROCKET_ADDRESS=127.0.0.1\"
Environment=\"ROCKET_PORT=1337\"
Environment=\"ROCKET_LOG=critical\"
Environment=\"ROCKET_SERVER_URL=https://$DOMAIN_NAME\"
# Optional environment variable
# Environment=\"ROCKET_RATE_LIMIT=2\" # default is 2
ExecStart=/var/www/bild/target/release/bild-server

[Install]
WantedBy=multi-user.target
" > /etc/systemd/system/bild-server.service

new_task "Starting up bild-server.service"
systemctl start bild-server && systemctl enable bild-server

green_bold "Thats it! Below is some final information:"

list "$(bold "Request URL:") https://$DOMAIN_NAME/i/upload" "$(bold "Form field:") data" "$(bold "Extra Headers:") Authorization: Bearer XXXXXXXXXXXXX" "$(bold "Image link:") {url}"