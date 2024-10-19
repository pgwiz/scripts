#!/bin/bash

# Get the VPS IP
vps_ip=$(curl -s http://ipinfo.io/ip)
sudo hostnamectl set-hostname "$vps_ip"
port_number=8004

# Install Git
sudo apt install git -y || { echo "Failed to install Git"; exit 1; }

# Prompt the user for input
echo "Please enter your project name:"
read -r project_name

# Validate GitHub repository link
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

# Change to the user's home directory
cd "$HOME" || { echo "Failed to change to home directory"; exit 1; }

# Clone the repository
git clone "$repo" "$project_name" || { echo "Failed to clone repository"; exit 1; }
cd "$project_name" || { echo "Failed to enter directory"; exit 1; }

# Create a virtual environment and activate it
python3 -m venv django_env || { echo "Failed to create virtual environment"; exit 1; }
source django_env/bin/activate

# Install necessary packages
sudo apt install -y python3-venv nginx || { echo "Failed to install required packages"; exit 1; }
pip install -r requirements.txt || { echo "Failed to install Python packages"; exit 1; }
pip install gunicorn || { echo "Failed to install Gunicorn"; exit 1; }

# Get the current repository path
repo_path=$(pwd)
echo "Current repository path: $repo_path"

# Collect static files
python3 manage.py collectstatic --noinput || { echo "Failed to collect static files"; exit 1; }

# Create configuration directory
mkdir -p conf

# Generate Gunicorn config
cat <<EOL > conf/gunicorn_config.py
command='${repo_path}/django_env/bin/gunicorn'
pythonpath='${repo_path}/${project_name}'
bind='${vps_ip}:${port_number}'  # Use the port variable
workers=3
EOL

# Prompt for domain input
read -p "Did you point any domain? (yes/no): " user_input
if [[ "$user_input" == "yes" ]]; then
    read -p "Please enter the domain name: " dm_name
else
    dm_name="$vps_ip"
fi

echo "The domain name is set to: $dm_name"

# Run Gunicorn in the background
# Replace with the correct command to restart your Gunicorn process
pkill gunicorn  # Kill existing Gunicorn processes
nohup gunicorn --config conf/gunicorn_config.py "${project_name}.wsgi:application" > gunicorn.log 2>&1 &

# Capture the PID of the Gunicorn process
gunicorn_pid=$!
echo "Gunicorn is running in the background with PID $gunicorn_pid."

# Create Nginx configuration
nginx_config="/etc/nginx/sites-available/$project_name"

# Remove the existing symbolic link if it exists
if [ -L "/etc/nginx/sites-enabled/$project_name" ]; then
    sudo rm "/etc/nginx/sites-enabled/$project_name"
    echo "Removed existing symbolic link for $project_name."
fi

sudo bash -c "cat <<EOL > $nginx_config
server {
    listen 80;
    server_name $dm_name;

    location /static/ {
        root $repo_path;  # Corrected root path
    }

    location / {
        include proxy_params;
        #proxy_set_header Host $dm_name;  # Add this line
        proxy_pass http://$vps_ip:${port_number};  # Use the port variable
    }
}
EOL"

# Create a symbolic link
sudo ln -s "$nginx_config" /etc/nginx/sites-enabled/

# Test Nginx configuration
if sudo nginx -t; then
    sudo systemctl reload nginx
    echo "Nginx configuration for $project_name has been set up."
else
    echo "Nginx configuration test failed. Please check the configuration."
fi



# ... [your existing code above] ...

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
ExecStart=$repo_path/django_env/bin/gunicorn --access-logfile - --workers 3 --bind ${vps_ip}:${port_number} ${project_name}.wsgi:application

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
