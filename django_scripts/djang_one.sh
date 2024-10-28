#!/bin/bash

set -e  # Exit on error

# Get the VPS IP and set hostname
vps_ip=$(curl -s http://ipinfo.io/ip)
sudo hostnamectl set-hostname "$vps_ip"
port_number=80  # Change to 80 for privileged port

# Check if Python 3.12.0 is installed
if ! command -v python3.12 &> /dev/null; then
    echo "Python 3.12.0 is not installed. Installing now..."
    
    # Install necessary dependencies for pyenv
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y build-essential libssl-dev libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm libffi-dev zlib1g-dev python3-openssl git

    # Install pyenv
    curl https://pyenv.run | bash

    # Add pyenv to your shell startup script
    echo 'export PATH="$HOME/.pyenv/bin:$PATH"' >> ~/.bashrc
    echo 'eval "$(pyenv init --path)"' >> ~/.bashrc
    echo 'eval "$(pyenv init -)"' >> ~/.bashrc
    echo 'eval "$(pyenv virtualenv-init -)"' >> ~/.bashrc
    source ~/.bashrc

    # Install Python 3.12 using pyenv
    pyenv install 3.12.0
    pyenv global 3.12.0
else
    echo "Python 3.12.0 is already installed."
fi

# Install necessary packages
sudo apt install git authbind -y

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

cat <<EOL > conf/gunicorn_config.py
command='${repo_path}/django_env/bin/gunicorn'
pythonpath='${repo_path}/${project_name}'
bind='${vps_ip}:${port_number}'
workers=3
EOL

# Get domain name from user
read -p "Did you point any domain? (yes/no): " user_input
if [[ "$user_input" == "yes" ]]; then
    read -p "Please enter the domain name: " dm_name
else
    dm_name="$vps_ip"
fi

echo "The domain name is set to: $dm_name"

# Run Gunicorn in the background
pkill gunicorn  # Kill existing Gunicorn processes
nohup authbind gunicorn --config conf/gunicorn_config.py "${project_name}.wsgi:application" > gunicorn.log 2>&1 &

gunicorn_pid=$!
echo "Gunicorn is running in the background with PID $gunicorn_pid."

# Create and test Nginx configuration
nginx_config="/etc/nginx/sites-available/$project_name"
ssl_cert="/etc/letsencrypt/live/$dm_name/fullchain.pem"
ssl_key="/etc/letsencrypt/live/$dm_name/privkey.pem"
static_root="/root/ctrack/staticfiles_build/static/"  # Adjust if needed

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
    exit 1
fi

echo "Setup complete."
