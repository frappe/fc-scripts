#!/usr/bin/env bash
# This script installs and runs the Flask application for on-prem failover management

set -e

IS_SETUP=false
if [[ "$1" == "setup" ]]; then
    IS_SETUP=true
fi

FAILOVER_ENV_NAME="failover-env"
FAILOVER_BASE_DIR="/root/press-on-prem-failover"
FAILOVER_APP_NAME="press-on-prem-failover"

install_python_dependencies() {
    echo "Installing dependencies in $FAILOVER_BASE_DIR"

    cd "$FAILOVER_BASE_DIR"
    apt update -y
    add-apt-repository -y ppa:deadsnakes/ppa
    apt update -y
    apt install -y python3.13 python3.13-venv

    python3.13 -m venv "$FAILOVER_ENV_NAME"

    "$FAILOVER_ENV_NAME/bin/python" -m pip install --upgrade pip
    "$FAILOVER_ENV_NAME/bin/python" -m pip install -r requirements.txt
}

install_and_setup_basic_auth() {
    echo "Installing apache2-utils for htpasswd..."

    apt update -y
    apt install -y apache2-utils

    read -p "Enter username for basic authentication: " USERNAME
    read -s -p "Enter password for basic authentication: " PASSWORD

    htpasswd -cb /etc/nginx/.htpasswd "$USERNAME" "$PASSWORD"
}

update_nginx_config() {
    echo "Updating nginx configuration..."

    cp "$FAILOVER_BASE_DIR/templates/nginx.conf" /etc/nginx/nginx.conf
    rm -rf /etc/nginx/sites-enabled/default # Remove default sites-enabled config since it has default server block

    nginx -t
}

setup_flask_daemon() {
    echo "Setting up Flask application as a systemd service daemon to start on boot..."

    SERVICE_FILE="/etc/systemd/system/$FAILOVER_APP_NAME.service"
    LOG_FILE="/var/log/$FAILOVER_APP_NAME.log"
    ERR_LOG_FILE="/var/log/$FAILOVER_APP_NAME.err.log"

    cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Flask application for press-on-prem failover management
After=network.target

[Service]
User=root
WorkingDirectory=$FAILOVER_BASE_DIR
ExecStart=$FAILOVER_BASE_DIR/$FAILOVER_ENV_NAME/bin/gunicorn --bind 127.0.0.1:5000 app:app
StandardOutput=append:$LOG_FILE
StandardError=append:$ERR_LOG_FILE
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    touch "$LOG_FILE" "$ERR_LOG_FILE"
    chmod 644 "$LOG_FILE" "$ERR_LOG_FILE"

    systemctl daemon-reload
    systemctl enable "$FAILOVER_APP_NAME"
     
    if systemctl list-units --full -all | grep -q "$FAILOVER_APP_NAME.service"; then
        systemctl restart "$FAILOVER_APP_NAME"
    else
        systemctl start "$FAILOVER_APP_NAME"
    fi

    echo "Flask application service setup complete and started."
}

setup_rq_worker_daemon() {
    WORKER_NAME="$FAILOVER_APP_NAME-worker"
    echo "Setting up RQ worker as a systemd service daemon to start on boot..."

    SERVICE_FILE="/etc/systemd/system/$WORKER_NAME.service"
    LOG_FILE="/var/log/$WORKER_NAME.log"
    ERR_LOG_FILE="/var/log/$WORKER_NAME.err.log"

    cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=RQ Worker For press-on-prem failover management
After=network.target

[Service]
User=root
WorkingDirectory=$FAILOVER_BASE_DIR
ExecStart=$FAILOVER_BASE_DIR/$FAILOVER_ENV_NAME/bin/rq worker
StandardOutput=append:$LOG_FILE
StandardError=append:$ERR_LOG_FILE
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    touch "$LOG_FILE" "$ERR_LOG_FILE"
    chmod 644 "$LOG_FILE" "$ERR_LOG_FILE"

    systemctl daemon-reload
    systemctl enable "$WORKER_NAME"
     
    if systemctl list-units --full -all | grep -q "$WORKER_NAME.service"; then
        systemctl restart "$WORKER_NAME"
    else
        systemctl start "$WORKER_NAME"
    fi

    echo "RQ Worker service setup complete and started."

}


if [[ -d "$FAILOVER_BASE_DIR" ]]; then
    echo "Found $FAILOVER_BASE_DIR"

    if [[ -f "$FAILOVER_BASE_DIR/app.py" ]]; then
        echo "Found Flask app (app.py)"

        if [[ "$IS_SETUP" == true ]]; then
            install_python_dependencies
            install_and_setup_basic_auth
            update_nginx_config
            setup_flask_daemon
            setup_rq_worker_daemon
        else
            echo "Setup flag not provided. Skipping setup."
        fi
    else
        echo "app.py not found in $FAILOVER_BASE_DIR"
        exit 1
    fi
else
    # In case things aren't preset then clone and simply setup everything
    echo "$FAILOVER_BASE_DIR not found. Cloning repository"
    git clone https://github.com/frappe/press-on-prem-failover.git "$FAILOVER_BASE_DIR"
    install_python_dependencies
    install_and_setup_basic_auth
    update_nginx_config
    setup_flask_daemon
    setup_rq_worker_daemon
    exit 1
fi
