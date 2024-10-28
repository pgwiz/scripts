#!/bin/bash

set -e  # Exit on error

# Function to get the VPS IP and set hostname
function set_hostname() {
    vps_ip=$(curl -s http://ipinfo.io/ip)
    sudo hostnamectl set-hostname "$vps_ip"
    port_number=80  # Change to 80 for privileged port
}

# Function to install necessary packages
function install_packages() {
    sudo apt update && sudo apt upgrade -y
    sudo apt install software-properties-common
    sudo add-apt-repository ppa:deadsnakes/ppa
    sudo apt update
    sudo apt install python3.12

    sudo apt install git authbind -y
}

# Function to setup authbind for port 80
function setup_authbind() {
    sudo touch /etc/authbind/byport/80
    sudo chmod 500 /etc/authbind/byport/80
    sudo chown "$USER" /etc/authbind/byport/80
}

# Function to prompt user for project name and repository
function prompt_user_input() {
    echo "Please enter your project name:"
    read -r project_name

    while true; do
        echo "Please enter a GitHub repository link for your project:"
        read -r repo

        if [[ $repo == *"github"* ]]; then
            echo "You entered a valid repository $repo. Continuing..."
            break
        else
            echo "Error: The input must contain the word 'github'. Please try again."
        fi
    done
}

# Function to clone the repository and set up the virtual environment
function setup_project() {
    cd "$HOME" || { echo "Failed to change to home directory"; exit 1; }
    git clone "$repo" "$project_name" || { echo "Failed to clone repository"; exit 1; }
    cd "$project_name" || { echo "Failed to enter directory"; exit 1; }

    python3 -m venv django_env || { echo "Failed to create virtual environment"; exit 1; }
    source django_env/bin/activate

    pip install -r requirements.txt || { echo "Failed to install Python packages"; exit 1; }
    pip install gunicorn || { echo "Failed to install Gunicorn"; exit 1; }
}

# Function to collect static files and run migrations
function prepare_django() {
    python3 manage.py collectstatic --noinput || { echo "Failed to collect static files"; exit 1; }
    python3 manage.py create_groups
    python3 manage.py makemigrations
    python3 manage.py migrate 
}

# Function to create Gunicorn configuration
function create_gunicorn_config() {
    local repo_path=$(pwd)
    mkdir -p conf

    cat <<EOL > conf/gunicorn_config.py
command='${repo_path}/django_env/bin/gunicorn'
pythonpath='${repo_path}/${project_name}'
bind='${vps_ip}:${port_number}'
workers=3
EOL
}

# Function to get domain name from user
function get_domain_name() {
    read -p "Did you point any domain? (yes/no): " user_input
    if [[ "$user_input" == "yes" ]]; then
        read -p "Please enter the domain name: " dm_name
    else
        dm_name="$vps_ip"
    fi

    echo "The domain name is set to: $dm_name"
}

# Function to run Gunicorn in the background
function run_gunicorn() {
    pkill gunicorn  # Kill existing Gunicorn processes
    nohup authbind gunicorn --config conf/gunicorn_config.py "${project_name}.wsgi:application" > gunicorn.log 2>&1 &

    local gunicorn_pid=$!
    echo "Gunicorn is running in the background with PID $gunicorn_pid."
}

# Function to create and test Nginx configuration
# Function to create and test Nginx configuration
function setup_nginx() {
    local nginx_config="/etc/nginx/sites-available/$project_name"
    local ssl_cert="/etc/letsencrypt/live/$dm_name/fullchain.pem"
    local ssl_key="/etc/letsencrypt/live/$dm_name/privkey.pem"
    local static_root="/root/ctrack/staticfiles_build/static/"  # Adjust if needed

    if [ -L "/etc/nginx/sites-enabled/$project_name" ]; then
        sudo rm "/etc/nginx/sites-enabled/$project_name"
        echo "Removed existing symbolic link for $project_name."
    fi

    sudo bash -c "cat <<EOL > $nginx_config
server {
    listen 80;
    server_name $dm_name www.$dm_name;

    # Redirect HTTP to HTTPS
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name $dm_name www.$dm_name;

    ssl_certificate $ssl_cert;
    ssl_certificate_key $ssl_key;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1h;

    access_log /var/log/nginx/$dm_name.access.log;
    error_log /var/log/nginx/$dm_name.error.log;

    location / {
        include proxy_params;
        proxy_pass http://127.0.0.1:${port_number};  # Forward requests to Gunicorn
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /static/ {
        alias $static_root;  # Serving static files
    }
}
EOL"

    sudo ln -s "$nginx_config" /etc/nginx/sites-enabled/

    if sudo nginx -t; then
        sudo systemctl reload nginx
        echo "Nginx configuration for $project_name has been set up."
    else
        echo "Nginx configuration test failed. Please check the configuration."
    fi
}


# Main script execution
set_hostname
install_packages
setup_authbind
prompt_user_input
setup_project
prepare_django
create_gunicorn_config
get_domain_name
run_gunicorn
setup_nginx
