#!/bin/sh

# Colors
GREEN=$(tput setaf 10)
YELLOW=$(tput setaf 11)
BLUE=$(tput setaf 12)
MAGENTA=$(tput setaf 13)
B=$(tput bold)
R=$(tput sgr0)

green_bold() {
  printf "%s\n" "${GREEN}${B}[Bild Install] $1${R}"
}

new_task() {
  printf "%s\n" "${BLUE}${B}[Bild Install] ->${R} $1"
}

info() {
  printf "%s\n" "${MAGENTA}${B}[Bild Install] ..${R} $1"
}

bold() {
  printf "%s\n" "${B}$1${R}"
}

warn() {
  printf "%s\n" "${YELLOW}${B}[Bild Install] !! $1${R}"
}

list() {
  for arg
  do printf "%s\n\r" "${MAGENTA}${B} - ${R}$arg"
  done
}

read_string() {
  printf "%s" "${BLUE}${B}[Bild Install] $1:${R} "; read -r
}

confirm() {
  if $2; then
    YN="[Y/n]"
  else
    YN="[y/N]"
  fi

  printf "%s" "$1 $YN "; read -r
  case $(echo "$REPLY" | tr '[:upper:]' '[:lower:]') in
    yes | y )
      return 0
      ;;
    no | n )
      return 1
      ;;
  esac
}

green_bold "Welcome to the bild installer!"

# Retrieve the distro name
DISTRO=$(cat /etc/*-release | grep DISTRIB_ID | awk -F"=" '{print $2}' | sed 's/"//')

# If distro is not ubuntu, warn the user of risk
if [ "$DISTRO" != "Ubuntu" ]; then
  warn "It looks like you're not running Ubuntu"
  if ! confirm "Things might not work as intended, continue anyways?" false; then
    green_bold "Exiting"
    exit 0
  fi
fi


new_task "Installing required packages:"
list "nginx" "certbot" "python3-certbot-nginx" "gcc"
# apt install nginx certbot python3-certbot-nginx gcc

new_task "Making sure nginx is up and running"
# systemctl start nginx && systemctl enable nginx

new_task "Installing rustup"
# curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

info "Adding cargo binaries to PATH"
# . "$HOME/.cargo/env"

info "Installing rustup nightly toolchain"
# rustup install nightly

read_string 'Enter your domain name (ex: your-domain.com)'
DOMAIN_NAME="i.$REPLY"

new_task "Creating nginx config file"
NGINX_CONF_FILE="/etc/nginx/sites-available/$DOMAIN_NAME.conf"
if [ -f "$NGINX_CONF_FILE" ]; then
  info "Looks like $NGINX_CONF_FILE already exists"
  if grep -q "server_name $DOMAIN_NAME www.$DOMAIN_NAME"; then
    info "Updating conf file with required fields"
    # sed "/server_name $DOMAIN_NAME www.$DOMAIN_NAME/a \tlocation / {\n\t\tproxy_pass http://127.0.0.1:1337;\n\t}" "$NGINX_CONF_FILE"
  fi
else
#   echo "server {
#   listen 80;
#   listen [::]:80;
#   server_name $DOMAIN_NAME www.$DOMAIN_NAME;
#   location / {
#     proxy_pass http://127.0.0.1:1337;
#   }
# }" > "$NGINX_CONF_FILE"

  info "Wrote server configuration to $(bold "$NGINX_CONF_FILE")"
fi

info "Symlinking $(bold "$NGINX_CONF_FILE") to $(bold "/etc/nginx/sites-enabled/")"
# ln -s "$NGINX_CONF_FILE" /etc/nginx/sites-enabled/

info "Reloading nginx"
# systemctl reload nginx

new_task "Start certificate generation with certbot"
if confirm "Do you want to generate certificates with certbot?" true; then
  info "Generating certs"
  # certbot --nginx -d "$DOMAIN_NAME" -d "www.$DOMAIN_NAME"

  info "Reloading nginx"
  # systemctl reload nginx
else
  info "Skipping cert generation"
fi


new_task "Cloning down bild repo to $(bold "/var/www/bild")"
# git clone https://gitlab.com/mWalrus/bild.git /var/www/bild

new_task "Compiling project binaries"
# cd /var/www/bild && rustup run nightly cargo build --release

info "Changing $(bold "/var/www/bild")'s owner to www-data"
# chown -R www-data: /var/www/bild

new_task "Adding systemd service $(bold /etc/systemd/system/bild-server.service)"
# echo "[Unit]
# Description=My Rocket application for $DOMAIN_NAME

# [Service]
# User=www-data
# Group=www-data
# # The user www-data should probably own that directory
# WorkingDirectory=/var/www/bild
# Environment=\"ROCKET_ENV=prod\"
# Environment=\"ROCKET_ADDRESS=127.0.0.1\"
# Environment=\"ROCKET_PORT=1337\"
# Environment=\"ROCKET_LOG=critical\"
# Environment=\"ROCKET_SERVER_URL=https://$DOMAIN_NAME\"
# # Optional environment variable
# # Environment=\"ROCKET_RATE_LIMIT=2\" # default is 2
# ExecStart=/var/www/bild/target/release/bild-server

# [Install]
# WantedBy=multi-user.target
# " > /etc/systemd/system/bild-server.service

info "Reloading systemd daemon"
# systemctl daemon-reload

info "Starting up bild-server.service"
# systemctl start bild-server && systemctl enable bild-server

new_task "Generating auth token"
# AUTH_TOKEN=$(/var/www/bild/target/release/bild-auth -t)

green_bold "Thats it! Below is some final information:"

list "$(bold "Request URL:") https://$DOMAIN_NAME/upload" "$(bold "Form field:") data" "$(bold "Extra Headers:") Authorization: Bearer $AUTH_TOKEN" "$(bold "Image link:") {url}"