#!/bin/bash

set -e  # Exit on error

# Get the VPS IP and set hostname
vps_ip=$(curl -s http://ipinfo.io/ip)
sudo hostnamectl set-hostname "$vps_ip"
port_number=8004  # Update to the port Gunicorn will use

# Install necessary packages
sudo apt update && sudo apt upgrade -y
sudo apt install -y build-essential libssl-dev libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm libffi-dev zlib1g-dev python3-openssl git authbind python3-venv python3-pip

# Setup authbind for port 80
sudo touch /etc/authbind/byport/80
sudo chmod 500 /etc/authbind/byport/80
sudo chown "$USER" /etc/authbind/byport/80

# Prompt user for project name and repository
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

# Clone the repository and set up the virtual environment
cd "$HOME" || { echo "Failed to change to home directory"; exit 1; }
git clone "$repo" "$project_name" || { echo "Failed to clone repository"; exit 1; }
cd "$project_name" || { echo "Failed to enter directory"; exit 1; }

python3 -m venv django_env || { echo "Failed to create virtual environment"; exit 1; }
source django_env/bin/activate

pip install -r requirements.txt || { echo "Failed to install Python packages"; exit 1; }
pip install gunicorn || { echo "Failed to install Gunicorn"; exit 1; }

# Collect static files and run migrations
python3 manage.py collectstatic --noinput || { echo "Failed to collect static files"; exit 1; }
python3 manage.py create_groups
python3 manage.py makemigrations
python3 manage.py migrate 

# Create Gunicorn configuration
mkdir -p conf
repo_path=$(pwd)

# Get domain name from user
read -p "Did you point any domain? (yes/no): " user_input
if [[ "$user_input" == "yes" ]]; then
    read -p "Please enter the domain name: " dm_name
else
    dm_name="$vps_ip"
fi

echo "The domain name is set to: $dm_name"

# Create a systemd service file for Gunicorn
service_file="/etc/systemd/system/gunicorn_$project_name.service"

sudo bash -c "cat <<EOL > $service_file
[Unit]
Description=gunicorn daemon for $project_name
After=network.target

[Service]
User=$USER
Group=www-data
WorkingDirectory=$repo_path
Environment='PATH=$repo_path/django_env/bin'
ExecStart=$repo_path/django_env/bin/gunicorn --access-logfile - --workers 3 --bind 127.0.0.1:${port_number} ${project_name}.wsgi:application

[Install]
WantedBy=multi-user.target
EOL"

# Reload systemd to recognize the new service
sudo systemctl daemon-reload

# Enable the Gunicorn service to start on boot
sudo systemctl enable "gunicorn_$project_name.service"

# Start the Gunicorn service
sudo systemctl start "gunicorn_$project_name.service"

echo "Gunicorn service for $project_name has been created and started."

# Create Nginx configuration using the provided template
nginx_config="/etc/nginx/sites-available/$project_name"

sudo bash -c "cat <<EOL > $nginx_config
server {
    listen 80;
    server_name $dm_name www.$dm_name;

    # Redirect HTTP to HTTPS
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;  # Listen on port 443 for HTTPS
    listen [::]:443 ssl;
    server_name $dm_name www.$dm_name;

    ssl_certificate /etc/letsencrypt/live/$dm_name/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$dm_name/privkey.pem;

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
        root $static_root;  # Serving static files
    }
}
EOL"

# Enable the Nginx configuration
sudo ln -s "$nginx_config" /etc/nginx/sites-enabled/

# Test and reload Nginx configuration
if sudo nginx -t; then
    sudo systemctl reload nginx
    echo "Nginx configuration for $project_name has been set up."
else
    echo "Nginx configuration test failed. Please check the configuration."
    exit 1
fi

echo "Setup complete."
