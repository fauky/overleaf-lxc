#!/bin/bash
set -e

TEXLIVE_MIRROR="https://mirror.ox.ac.uk/sites/ctan.org/systems/texlive/tlnet"

OVERLEAF_DIR="/overleaf"

install_os_packages() {
  echo "Updating OS..."
  apt update && apt -y upgrade

  apt install -y \
    unattended-upgrades \
    build-essential \
    wget \
    net-tools \
    unzip \
    time \
    imagemagick \
    optipng \
    strace \
    nginx \
    git \
    python3 \
    python-is-python3 \
    zlib1g-dev \
    libpcre3-dev \
    gettext-base \
    libwww-perl \
    ca-certificates \
    curl \
    gnupg \
    qpdf \
    gpg \
    redis-server \
    lsb-release \
    software-properties-common \
    xz-utils

  unattended-upgrade --verbose --no-minimal-upgrade-steps
}


# Install Node.js
install_node_js() {
  echo "Installing Node.js v22..."
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/trusted.gpg.d/nodesource.gpg
  echo "deb [signed-by=/etc/apt/trusted.gpg.d/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
  apt update && apt install -y nodejs
}

install_mongo_db() {
  echo "Installing MongoDB..."
  curl -fsSL https://pgp.mongodb.com/server-8.0.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/mongodb-server-8.0.gpg
  echo "deb [ signed-by=/etc/apt/trusted.gpg.d/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/8.0 multiverse" > /etc/apt/sources.list.d/mongodb-org-8.0.list
  apt update && apt install -y mongodb-org

  # add replica set
  echo -e "\nreplication:\n  replSetName: overleaf" >> /etc/mongod.conf
  systemctl restart mongod

  # Wait a few seconds to ensure MongoDB has restarted
  sleep 3

  # initialize replica set
  mongosh --eval "rs.initiate()"
}

install_texlive() {
  echo "Installing TeX Live..."
  mkdir -p "/tmp/texlive" && cd "/tmp/texlive"

  wget https://tug.org/texlive/files/texlive.asc
  gpg --import texlive.asc
  rm texlive.asc

  wget ${TEXLIVE_MIRROR}/install-tl-unx.tar.gz
  wget ${TEXLIVE_MIRROR}/install-tl-unx.tar.gz.sha512
  wget ${TEXLIVE_MIRROR}/install-tl-unx.tar.gz.sha512.asc

  gpg --verify install-tl-unx.tar.gz.sha512.asc
  sha512sum -c install-tl-unx.tar.gz.sha512

  tar -xzf install-tl-unx.tar.gz --strip-components=1

  cat <<EOF > texlive.profile
selected_scheme scheme-basic
tlpdbopt_autobackup 0
tlpdbopt_install_docfiles 0
tlpdbopt_install_srcfiles 0
EOF

  ./install-tl -profile texlive.profile -repository ${TEXLIVE_MIRROR}

  export PATH="/usr/local/texlive/$(date +%Y)/bin/x86_64-linux:$PATH"

  tlmgr install --repository ${TEXLIVE_MIRROR} \
    latexmk \
    texcount \
    synctex \
    etoolbox \
    xetex

  tlmgr path add

  # clean up
  cd /
  rm -rf /tmp/texlive
}

install_overleaf() {
  echo "Installaing Overleaf Community Edition..."
  echo "Creating Overleaf directories and user..."

  mkdir -p /var/lib/overleaf
  mkdir -p /var/log/overleaf
  mkdir -p /var/lib/overleaf/data/template_files

  chown www-data:www-data /var/lib/overleaf
  chown www-data:www-data /var/log/overleaf
  chown www-data:www-data /var/lib/overleaf/data/template_files

  echo "Getting Overleaf sources..."
  cd /tmp
  git clone https://github.com/overleaf/overleaf.git
  cd overleaf

  echo "Setting up Overleaf Community Edition..."
  mkdir -p "$OVERLEAF_DIR"

  # Copy required source files
  echo "Copying source files..."
  cp server-ce/genScript.js "$OVERLEAF_DIR/genScript.js"
  cp server-ce/services.js "$OVERLEAF_DIR/services.js"
  cp package.json package-lock.json "$OVERLEAF_DIR/"
  cp -r libraries "$OVERLEAF_DIR/"
  cp -r services "$OVERLEAF_DIR/"
  cp -r patches "$OVERLEAF_DIR/"

  # Global settings
  mkdir -p /etc/overleaf
  cp server-ce/config/env.sh /etc/overleaf/env.sh

  # Nginx configuration
  echo "Configuring nginx..."
  rm -f /etc/nginx/nginx.conf /etc/nginx/sites-enabled/default
  mkdir -p /etc/nginx/templates
  cp server-ce/nginx/nginx.conf.template /etc/nginx/templates/nginx.conf.template
  cp server-ce/nginx/overleaf.conf /etc/nginx/sites-enabled/overleaf.conf
  cp server-ce/nginx/clsi-nginx.conf /etc/nginx/sites-enabled/clsi-nginx.conf
  sed -i 's/^\s*\(daemon\s\+off;\)/# \1/' /etc/nginx/templates/nginx.conf.template

  # Logrotate
  echo "Setting up logrotate..."
  cp server-ce/logrotate/overleaf /etc/logrotate.d/overleaf
  chmod 644 /etc/logrotate.d/overleaf

  # Cron jobs
  echo "Installing cron tasks..."
  cp -r server-ce/cron "$OVERLEAF_DIR/cron"
  cp server-ce/config/crontab-history /etc/cron.d/crontab-history
  chmod 600 /etc/cron.d/crontab-history
  cp server-ce/config/crontab-deletion /etc/cron.d/crontab-deletion
  chmod 600 /etc/cron.d/crontab-deletion

  # Init scripts
  echo "Copying init scripts..."
  mkdir -p /etc/my_init.d /etc/my_init.pre_shutdown.d
  cp -r server-ce/init_scripts/* /etc/my_init.d/
  cp -r server-ce/init_preshutdown_scripts/* /etc/my_init.pre_shutdown.d/

  # App settings
  cp server-ce/config/settings.js /etc/overleaf/settings.js

  # History service configs
  mkdir -p "$OVERLEAF_DIR/services/history-v1/config/"
  cp server-ce/config/production.json "$OVERLEAF_DIR/services/history-v1/config/production.json"
  cp server-ce/config/custom-environment-variables.json "$OVERLEAF_DIR/services/history-v1/config/custom-environment-variables.json"

  # Grunt thin wrapper
  cp server-ce/bin/grunt /usr/local/bin/grunt
  chmod +x /usr/local/bin/grunt

  # History queue tools
  mkdir -p "$OVERLEAF_DIR/bin"
  cp server-ce/bin/flush-history-queues "$OVERLEAF_DIR/bin/flush-history-queues"
  chmod +x "$OVERLEAF_DIR/bin/flush-history-queues"
  cp server-ce/bin/force-history-resyncs "$OVERLEAF_DIR/bin/force-history-resyncs"
  chmod +x "$OVERLEAF_DIR/bin/force-history-resyncs"

  # Latexmkrc
  mkdir -p /usr/local/share/latexmk
  cp server-ce/config/latexmkrc /usr/local/share/latexmk/LatexMk


  # Write environment variables to /etc/container_environment.sh
  # Site status file
  SITE_MAINTENANCE_FILE="/etc/overleaf/site_status"
  touch "$SITE_MAINTENANCE_FILE"
  echo "Exporting environment variables..."
  cat << EOF > /etc/container_environment.sh
export SITE_MAINTENANCE_FILE=${SITE_MAINTENANCE_FILE}
export OVERLEAF_CONFIG=/etc/overleaf/settings.js
export WEB_API_USER=overleaf
export ADMIN_PRIVILEGE_AVAILABLE=true
export OVERLEAF_APP_NAME="Overleaf"
export OPTIMISE_PDF=true
export KILL_PROCESS_TIMEOUT=55
export KILL_ALL_PROCESSES_TIMEOUT=55
export GRACEFUL_SHUTDOWN_DELAY_SECONDS=1
export NODE_ENV=production
export LOG_LEVEL=info
export MONGO_INITDB_DATABASE=sharelatex
export OVERLEAF_MONGO_URL=mongodb://localhost/sharelatex
export OVERLEAF_REDIS_HOST=localhost
export REDIS_HOST=localhost
export ENABLED_LINKED_FILE_TYPES='project_file,project_output_file'
export ENABLE_CONVERSIONS='true'
export EMAIL_CONFIRMATION_DISABLED='true'
EOF

  # Install npm dependencies and build assets
  echo "Installing npm packages and compiling assets..."
  cd "$OVERLEAF_DIR"
  node genScript install | bash
  node genScript compile | bash

  # Run initialization scripts
  echo "Running initialization scripts in $INIT_DIR..."
  INIT_DIR="/etc/my_init.d"
  mkdir -p /etc/container_environment

  # Iterate over files in lexicographic order
  for script in "$INIT_DIR"/*; do
    if [ -f "$script" ] && [ -x "$script" ]; then
      echo "Executing: $script"
      "$script"
    else
      echo "Skipping: $script (not executable or not a file)"
    fi
  done

  # One of the init_scripts sets dockerhost to gateway's address
  # This needs to be set to localhost
  echo "Set dockerhost to localhost in /etc/hosts"
  sed -i '/dockerhost/c\127.0.0.1       dockerhost' /etc/hosts

  ## Load all environmental variables to /etc/overleaf/env.sh
  echo "Updating environmental variables..."
  cat /etc/container_environment.sh >> /etc/overleaf/env.sh

  SRC_DIR="/etc/container_environment"
  DEST_FILE="/etc/overleaf/env.sh"

  for filepath in "$SRC_DIR"/*; do
      [ -f "$filepath" ] || continue  # skip if not a regular file

      varname=$(basename "$filepath")
      value=$(<"$filepath")

      # Escape value for inclusion in shell script
      escaped_value=$(printf '%q' "$value")

      echo "$varname=$escaped_value" >> "$DEST_FILE"
  done

  # remove 'export' to make the file work as systemd EnvironmentFile
  sed -i 's/^export //' /etc/overleaf/env.sh
}

install_systemd_services() {
  # Define systemd unit files
  declare -A UNITS

# 1. chat
UNITS["overleaf-chat.service"]='
[Unit]
Description=Overleaf Chat Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/overleaf/services/chat
EnvironmentFile=/etc/overleaf/env.sh
Environment=LISTEN_ADDRESS=127.0.0.1
ExecStart=/usr/bin/node /overleaf/services/chat/app.js
StandardOutput=append:/var/log/overleaf/chat.log
StandardError=append:/var/log/overleaf/chat.log
User=www-data
Restart=on-failure

[Install]
WantedBy=multi-user.target
'

# 2. clsi
UNITS["overleaf-clsi.service"]='
[Unit]
Description=Overleaf CLSI Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/overleaf/services/clsi
EnvironmentFile=/etc/overleaf/env.sh
Environment=LISTEN_ADDRESS=127.0.0.1
ExecStart=/usr/bin/node /overleaf/services/clsi/app.js
StandardOutput=append:/var/log/overleaf/clsi.log
StandardError=append:/var/log/overleaf/clsi.log
User=www-data
Restart=on-failure

[Install]
WantedBy=multi-user.target
'

# 3. contacts
UNITS["overleaf-contacts.service"]='
[Unit]
Description=Overleaf Contacts Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/overleaf/services/contacts
EnvironmentFile=/etc/overleaf/env.sh
Environment=LISTEN_ADDRESS=127.0.0.1
ExecStart=/usr/bin/node /overleaf/services/contacts/app.js
StandardOutput=append:/var/log/overleaf/contacts.log
StandardError=append:/var/log/overleaf/contacts.log
User=www-data
Restart=on-failure

[Install]
WantedBy=multi-user.target
'

# 4. docstore
UNITS["overleaf-docstore.service"]='
[Unit]
Description=Overleaf Docstore Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/overleaf/services/docstore
EnvironmentFile=/etc/overleaf/env.sh
Environment=LISTEN_ADDRESS=127.0.0.1
ExecStart=/usr/bin/node /overleaf/services/docstore/app.js
StandardOutput=append:/var/log/overleaf/docstore.log
StandardError=append:/var/log/overleaf/docstore.log
User=www-data
Restart=on-failure

[Install]
WantedBy=multi-user.target
'

# 5. document-updater
UNITS["overleaf-document-updater.service"]='
[Unit]
Description=Overleaf Document Updater Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/overleaf/services/document-updater
EnvironmentFile=/etc/overleaf/env.sh
Environment=LISTEN_ADDRESS=127.0.0.1
ExecStart=/usr/bin/node /overleaf/services/document-updater/app.js
StandardOutput=append:/var/log/overleaf/document-updater.log
StandardError=append:/var/log/overleaf/document-updater.log
User=www-data
Restart=on-failure

[Install]
WantedBy=multi-user.target
'

# 6. filestore
UNITS["overleaf-filestore.service"]='
[Unit]
Description=Overleaf Filestore Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/overleaf/services/filestore
EnvironmentFile=/etc/overleaf/env.sh
Environment=LISTEN_ADDRESS=127.0.0.1
ExecStart=/usr/bin/node /overleaf/services/filestore/app.js
StandardOutput=append:/var/log/overleaf/filestore.log
StandardError=append:/var/log/overleaf/filestore.log
User=www-data
Restart=on-failure

[Install]
WantedBy=multi-user.target
'

# 7. history-v1
UNITS["overleaf-history-v1.service"]='
[Unit]
Description=Overleaf History v1 Service
After=network.target

[Service]
Type=simple
EnvironmentFile=/etc/overleaf/env.sh
Environment=NODE_CONFIG_DIR=/overleaf/services/history-v1/config
ExecStart=/usr/bin/node /overleaf/services/history-v1/app.js
StandardOutput=append:/var/log/overleaf/history-v1.log
StandardError=append:/var/log/overleaf/history-v1.log
User=www-data
Restart=on-failure

[Install]
WantedBy=multi-user.target
'

# 8. notifications
UNITS["overleaf-notifications.service"]='
[Unit]
Description=Overleaf Notifications Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/overleaf/services/notifications
EnvironmentFile=/etc/overleaf/env.sh
Environment=LISTEN_ADDRESS=127.0.0.1
ExecStart=/usr/bin/node /overleaf/services/notifications/app.js
StandardOutput=append:/var/log/overleaf/notifications.log
StandardError=append:/var/log/overleaf/notifications.log
User=www-data
Restart=on-failure

[Install]
WantedBy=multi-user.target
'

# 9. project-history
UNITS["overleaf-project-history.service"]='
[Unit]
Description=Overleaf Project History Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/overleaf/services/project-history
EnvironmentFile=/etc/overleaf/env.sh
Environment=LISTEN_ADDRESS=127.0.0.1
ExecStart=/usr/bin/node /overleaf/services/project-history/app.js
StandardOutput=append:/var/log/overleaf/project-history.log
StandardError=append:/var/log/overleaf/project-history.log
User=www-data
Restart=on-failure

[Install]
WantedBy=multi-user.target
'

# 10. real-time
UNITS["overleaf-real-time.service"]='
[Unit]
Description=Overleaf Real-Time Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/overleaf/services/real-time
EnvironmentFile=/etc/overleaf/env.sh
Environment=LISTEN_ADDRESS=127.0.0.1
ExecStart=/usr/bin/node /overleaf/services/real-time/app.js
StandardOutput=append:/var/log/overleaf/real-time.log
StandardError=append:/var/log/overleaf/real-time.log
User=www-data
Restart=on-failure

[Install]
WantedBy=multi-user.target
'

# 11. web-api
UNITS["overleaf-web-api.service"]='
[Unit]
Description=Overleaf Web API Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/overleaf/services/web
EnvironmentFile=/etc/overleaf/env.sh
Environment=LISTEN_ADDRESS=0.0.0.0
Environment=ENABLED_SERVICES=api
Environment=METRICS_APP_NAME=web-api
ExecStart=/usr/bin/node /overleaf/services/web/app.mjs
StandardOutput=append:/var/log/overleaf/web-api.log
StandardError=append:/var/log/overleaf/web-api.log
User=www-data
Restart=on-failure

[Install]
WantedBy=multi-user.target
'

# 12. web
UNITS["overleaf-web.service"]='
[Unit]
Description=Overleaf Web UI Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/overleaf/services/web
EnvironmentFile=/etc/overleaf/env.sh
Environment=LISTEN_ADDRESS=127.0.0.1
Environment=ENABLED_SERVICES=web
Environment=WEB_PORT=4000
ExecStart=/usr/bin/node /overleaf/services/web/app.mjs
StandardOutput=append:/var/log/overleaf/web.log
StandardError=append:/var/log/overleaf/web.log
User=www-data
Restart=on-failure

[Install]
WantedBy=multi-user.target
'

  # Install systemd services
  echo "Installing systemd service units..."

  # Write each systemd unit file to disk
  for unit in "${!UNITS[@]}"; do
    echo "  Installing $unit"
    echo "${UNITS[$unit]}" > "/etc/systemd/system/$unit"
  done

  echo "Reloading systemd daemon..."
  systemctl daemon-reload

  echo "Enabling Overleaf services..."
  for unit in "${!UNITS[@]}"; do
    systemctl enable "$unit"
  done

  echo "Starting Overleaf services..."
  for unit in "${!UNITS[@]}"; do
    systemctl start "$unit"
  done

  echo "All Overleaf services installed and started."
}

show_login_info() {
  echo "Create first account at: http://$(hostname -I | awk '{print $1}')/launchpad"
}

## main function
main() {
  install_os_packages
  install_node_js
  install_mongo_db
  install_texlive
  install_overleaf
  install_systemd_services
  show_login_info
}

### Start Here ###
## Check for sudo
[[ $EUID -ne 0 ]] && { echo "This script requires root access; please run with sudo."; exit 1; }

main "$@"
