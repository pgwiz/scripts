#!/bin/bash

# Prompt for project name
read -p "Please enter the project name: " project_name
nginx_config="/etc/nginx/sites-available/$project_name"  # Nginx config file path
vps_ip=$(curl -s http://ipinfo.io/ip)                    # Get the VPS IP
port_number=8004                                          # Change if necessary

# Prompt for domain input
read -p "Please enter the domain name: " dm_name

# Ensure the Nginx configuration file exists
if [ ! -f "$nginx_config" ]; then
    echo "Nginx configuration file $nginx_config does not exist. Please create it first."
    exit 1
fi

# Install Certbot
if ! command -v certbot &> /dev/null; then
    echo "Certbot not found. Installing..."
    sudo apt update
    sudo apt install certbot python3-certbot-nginx -y || { echo "Failed to install Certbot"; exit 1; }
fi

# Obtain SSL certificate
email="info@$dm_name"
echo "Obtaining SSL certificate for $dm_name..."
sudo certbot --nginx -d "$dm_name" -d "www.$dm_name" --agree-tos --non-interactive --email "$email" || { echo "Failed to obtain SSL certificate"; exit 1; }

# Update Nginx configuration for SSL
sudo bash -c "cat <<EOL >> $nginx_config

server {
    listen 443 ssl;
    server_name $dm_name;

    ssl_certificate /etc/letsencrypt/live/$dm_name/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$dm_name/privkey.pem;

    location / {
        include proxy_params;
        proxy_pass http://$vps_ip:$port_number;  # Use the port variable
    }
}
EOL"

# Test Nginx configuration
echo "Testing Nginx configuration..."
if sudo nginx -t; then
    sudo systemctl reload nginx
    echo "SSL configuration for $dm_name has been set up successfully."
else
    echo "Nginx configuration test failed. Please check the configuration."
fi
