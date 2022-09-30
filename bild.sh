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
  printf "%s" "${BLUE}${B}[Bild Install] $1:${R} "; read -r REPLY
}

validate_number_input() {
  if [ -z "$REPLY" ] || ! echo "$REPLY" | grep -q "^[0-9]*$"; then
    REPLY="$1"
  fi
}

confirm() {
  if $2; then
    YN="[Y/n]"
  else
    YN="[y/N]"
  fi

  printf "%s" "$1 $YN "; read -r REPLY
  case $(echo "$REPLY" | tr '[:upper:]' '[:lower:]') in
    yes | y )
      return 0
      ;;
    no | n )
      return 1
      ;;
  esac
}

install_packages() {
  new_task "Installing required packages:"
  list "nginx" "certbot" "python3-certbot-nginx" "gcc"
  apt install nginx certbot python3-certbot-nginx gcc
}

green_bold "Welcome to the bild installer!"

case "$1" in
  --update | -u )
    install_packages

    new_task "Cloning down bild repo to $(bold "/var/www/bild")"
    git clone https://gitlab.com/mWalrus/bild.git /var/www/bild

    new_task "Compiling project binaries"
    cd /var/www/bild && rustup run nightly cargo build --release
    
    new_task "Reloading bild-server service"
    systemctl stop bild-server && systemctl start bild-server
    exit 0
  ;;
  --help | -h )
    echo "usage: $(basename "$0") [option...]"
    echo
    echo "    -u, --update       Update an existing installation of Bild"
    echo "    -h, --help         Display this help screen"
    echo
    exit 0
esac

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

install_packages

new_task "Making sure nginx is up and running"
systemctl start nginx && systemctl enable nginx

new_task "Installing rustup"
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

info "Adding cargo binaries to PATH"
. "$HOME/.cargo/env"

info "Installing rustup nightly toolchain"
rustup install nightly

read_string 'Enter your domain name (ex: your-domain.com)'
DOMAIN_NAME="i.$REPLY"

new_task "Creating nginx config file"
NGINX_CONF_FILE="/etc/nginx/sites-available/$DOMAIN_NAME.conf"
if [ -f "$NGINX_CONF_FILE" ]; then
  info "Looks like $NGINX_CONF_FILE already exists"
  if grep -q "server_name $DOMAIN_NAME www.$DOMAIN_NAME"; then
    info "Updating conf file with required fields"
    sed "/server_name $DOMAIN_NAME www.$DOMAIN_NAME/a \tlocation / {\n\t\tproxy_pass http://127.0.0.1:1337;\n\t}" "$NGINX_CONF_FILE"
  fi
else
  echo "server {
  listen 80;
  listen [::]:80;
  server_name $DOMAIN_NAME www.$DOMAIN_NAME;
  location / {
    proxy_pass http://127.0.0.1:1337;
  }
}" > "$NGINX_CONF_FILE"

  info "Wrote server configuration to $(bold "$NGINX_CONF_FILE")"
fi

info "Symlinking $(bold "$NGINX_CONF_FILE") to $(bold "/etc/nginx/sites-enabled/")"
ln -s "$NGINX_CONF_FILE" /etc/nginx/sites-enabled/

info "Reloading nginx"
systemctl reload nginx

new_task "Start certificate generation with certbot"
if confirm "Do you want to generate certificates with certbot?" true; then
  info "Generating certs"
  certbot --nginx -d "$DOMAIN_NAME" -d "www.$DOMAIN_NAME"

  info "Reloading nginx"
  systemctl reload nginx
else
  info "Skipping cert generation"
fi


new_task "Cloning down bild repo to $(bold "/var/www/bild")"
git clone https://gitlab.com/mWalrus/bild.git /var/www/bild

new_task "Compiling project binaries"
cd /var/www/bild && rustup run nightly cargo build --release

info "Changing $(bold "/var/www/bild")'s owner to www-data"
chown -R www-data: /var/www/bild

new_task "Adding systemd service $(bold /etc/systemd/system/bild-server.service)"

read_string "Enter limit of uploads per second (default: 2)"

validate_number_input 2
RATE_LIMIT=$REPLY

read_string "Turn on periodic file deletion (ON=1, OFF=0, default: 1)"

validate_number_input 1
GARBAGE_COLLECTOR=$REPLY

if [ "$GARBAGE_COLLECTOR" != "0" ] && [ "$GARBAGE_COLLECTOR" != "1" ]; then
  GARBAGE_COLLECTOR="1"
fi

if [ "$GARBAGE_COLLECTOR" = "1" ]; then
  read_string "Enter how many weeks files are allowed to live for (default: 2)"

  validate_number_input 2
  NUM_WEEKS=$REPLY
else
  NUM_WEEKS="2"
fi

read_string "Enter max file size (default: 20 MiB)"
UPLOAD_MAX_SIZE=$REPLY

echo "[Unit]
Description=My Rocket application for $DOMAIN_NAME

[Service]
User=www-data
Group=www-data
# The user www-data should probably own that directory
WorkingDirectory=/var/www/bild
Environment=\"ROCKET_ADDRESS=127.0.0.1\"
Environment=\"ROCKET_PORT=1337\"
Environment=\"ROCKET_SERVER_URL=https://$DOMAIN_NAME\"
Environment=\"ROCKET_GARBAGE_COLLECTOR=$GARBAGE_COLLECTOR\"
Environment=\"ROCKET_RATE_LIMIT=$RATE_LIMIT\"
Environment=\"ROCKET_FILE_AGE_WEEKS=$NUM_WEEKS\"
Environment=\"ROCKET_UPLOAD_MAX_SIZE=$UPLOAD_MAX_SIZE\"
ExecStart=/var/www/bild/target/release/bild-server

[Install]
WantedBy=multi-user.target
" > /etc/systemd/system/bild-server.service

info "Reloading systemd daemon"
systemctl daemon-reload

info "Starting up bild-server.service"
systemctl start bild-server && systemctl enable bild-server

new_task "Generating auth token"
AUTH_TOKEN=$(/var/www/bild/target/release/bild-auth -t)

green_bold "Thats it! Below is some final information:"

list "$(bold "Request URL:") https://$DOMAIN_NAME/upload" "$(bold "Form field:") data" "$(bold "Extra Headers:") Authorization: Bearer $AUTH_TOKEN" "$(bold "Image link:") {url}"

info "Dont forget to forward port 80 and 443 on your VPS if needed. :)"