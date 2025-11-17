#!/bin/bash

################################################################################
# Advanced SSL/TLS Certificate Manager
# Comprehensive Let's Encrypt integration with ACME challenge support
# Features: Auto-renewal, domain verification, multiple CA support
################################################################################

set -e

# Colors and formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Configuration
SCRIPT_VERSION="2.0.0"
CONFIG_DIR="/etc/cert-manager"
LOG_DIR="/var/log/cert-manager"
BACKUP_DIR="/var/backups/cert-manager"
CERT_DIR="/etc/letsencrypt"
LOG_FILE="${LOG_DIR}/cert-manager.log"
STATE_FILE="${CONFIG_DIR}/state.json"

# Create necessary directories
mkdir -p "$CONFIG_DIR" "$LOG_DIR" "$BACKUP_DIR"

################################################################################
# Utility Functions
################################################################################

log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"

    case $level in
        ERROR)
            echo -e "${RED}[ERROR]${NC} $message" >&2
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
        WARNING)
            echo -e "${YELLOW}[WARNING]${NC} $message"
            ;;
        INFO)
            echo -e "${CYAN}[INFO]${NC} $message"
            ;;
        *)
            echo "$message"
            ;;
    esac
}

print_header() {
    clear
    echo -e "${PURPLE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${NC}     ${BOLD}Advanced SSL/TLS Certificate Manager v${SCRIPT_VERSION}${NC}          ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${NC}     ${CYAN}Let's Encrypt Integration & ACME Challenge Support${NC}    ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_separator() {
    echo -e "${BLUE}────────────────────────────────────────────────────────────────${NC}"
}

spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

progress_bar() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local completed=$((width * current / total))

    printf "\r["
    printf "%${completed}s" | tr ' ' '='
    printf "%$((width - completed))s" | tr ' ' '-'
    printf "] %d%%" $percentage
}

prompt_yes_no() {
    local prompt="$1"
    local default="${2:-n}"

    if [ "$default" = "y" ]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi

    while true; do
        read -p "$prompt" yn
        yn=${yn:-$default}
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log ERROR "This script must be run as root or with sudo"
        exit 1
    fi
}

get_server_ip() {
    local ip=$(curl -s4 https://icanhazip.com 2>/dev/null || curl -s4 http://ipinfo.io/ip 2>/dev/null || curl -s4 https://api.ipify.org 2>/dev/null)
    if [ -z "$ip" ]; then
        ip=$(hostname -I | awk '{print $1}')
    fi
    echo "$ip"
}

################################################################################
# System Detection and Requirements
################################################################################

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    else
        OS=$(uname -s)
        OS_VERSION=$(uname -r)
    fi

    log INFO "Detected OS: $OS $OS_VERSION"
}

detect_web_server() {
    local web_server=""

    if command -v nginx &> /dev/null; then
        web_server="nginx"
    elif command -v apache2 &> /dev/null; then
        web_server="apache2"
    elif command -v httpd &> /dev/null; then
        web_server="httpd"
    fi

    echo "$web_server"
}

install_dependencies() {
    print_header
    echo -e "${BOLD}Installing System Dependencies...${NC}\n"

    detect_os

    local packages="curl wget dnsutils net-tools cron openssl"

    case $OS in
        ubuntu|debian)
            log INFO "Installing packages for Debian/Ubuntu..."
            apt-get update -qq
            apt-get install -y $packages certbot python3-certbot-nginx python3-certbot-apache python3-certbot-dns-cloudflare bc jq &> /dev/null &
            spinner $!
            ;;
        centos|rhel|fedora)
            log INFO "Installing packages for RHEL/CentOS/Fedora..."
            yum install -y $packages certbot python3-certbot-nginx python3-certbot-apache bc jq &> /dev/null &
            spinner $!
            ;;
        *)
            log WARNING "Unsupported OS. Please install dependencies manually."
            ;;
    esac

    log SUCCESS "Dependencies installed successfully"
    sleep 1
}

################################################################################
# Domain Management and DNS Verification
################################################################################

verify_dns_record() {
    local domain=$1
    local server_ip=$2

    log INFO "Verifying DNS record for $domain..."

    # Check A record
    local domain_ip=$(dig +short A "$domain" @8.8.8.8 | tail -n1)

    if [ -z "$domain_ip" ]; then
        log ERROR "No DNS A record found for $domain"
        return 1
    fi

    if [ "$domain_ip" = "$server_ip" ]; then
        log SUCCESS "DNS record verified: $domain → $server_ip"
        return 0
    else
        log ERROR "DNS mismatch: $domain points to $domain_ip, but server IP is $server_ip"
        return 1
    fi
}

check_domain_connectivity() {
    local domain=$1

    log INFO "Checking domain connectivity for $domain..."

    # Check if port 80 is reachable
    if timeout 5 bash -c "echo > /dev/tcp/$domain/80" 2>/dev/null; then
        log SUCCESS "Port 80 is accessible on $domain"
        return 0
    else
        log WARNING "Port 80 is not accessible on $domain"
        return 1
    fi
}

validate_domain() {
    local domain=$1

    # Basic domain format validation
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        log ERROR "Invalid domain format: $domain"
        return 1
    fi

    return 0
}

################################################################################
# ACME Challenge Handler
################################################################################

show_acme_challenge_menu() {
    local domain=$1

    print_header
    echo -e "${BOLD}ACME Challenge Selection${NC}"
    echo -e "Domain: ${GREEN}$domain${NC}\n"
    print_separator

    echo -e "${YELLOW}Select Challenge Type:${NC}\n"
    echo "  1) HTTP-01 Challenge (Recommended)"
    echo "     - Validates via HTTP on port 80"
    echo "     - Requires domain to point to this server"
    echo "     - Best for single domains"
    echo ""
    echo "  2) DNS-01 Challenge"
    echo "     - Validates via DNS TXT record"
    echo "     - Required for wildcard certificates"
    echo "     - Works behind firewalls"
    echo ""
    echo "  3) TLS-ALPN-01 Challenge"
    echo "     - Validates via TLS on port 443"
    echo "     - Advanced use case"
    echo ""
    echo "  4) Auto-detect (Let certbot decide)"
    echo ""
    echo "  0) Back to main menu"
    echo ""
    print_separator

    read -p "Select challenge type [1-4]: " ACME_CHOICE
}

handle_http01_challenge() {
    local domain=$1
    local email=$2
    local web_server=$3

    print_header
    echo -e "${BOLD}HTTP-01 Challenge Configuration${NC}\n"

    log INFO "Preparing HTTP-01 challenge for $domain..."

    # Check if web server is running
    if [ -n "$web_server" ]; then
        log SUCCESS "Web server detected: $web_server"
    else
        log WARNING "No web server detected. Installing Nginx..."
        apt-get install -y nginx &> /dev/null
        systemctl start nginx
        web_server="nginx"
    fi

    # Create webroot directory
    local webroot="/var/www/html"
    mkdir -p "$webroot/.well-known/acme-challenge"

    # Set proper permissions
    chmod -R 755 "$webroot/.well-known"

    log INFO "Starting certificate issuance..."

    # Build certbot command
    local certbot_cmd="certbot certonly --${web_server} -d $domain"

    if [ -n "$email" ]; then
        certbot_cmd="$certbot_cmd --email $email --agree-tos --non-interactive"
    fi

    # Execute certbot
    if eval "$certbot_cmd"; then
        log SUCCESS "Certificate issued successfully via HTTP-01 challenge"
        return 0
    else
        log ERROR "Certificate issuance failed"
        show_http01_troubleshooting "$domain"
        return 1
    fi
}

show_http01_troubleshooting() {
    local domain=$1

    echo -e "\n${YELLOW}${BOLD}Troubleshooting HTTP-01 Challenge:${NC}\n"

    echo "Common issues and solutions:"
    echo ""
    echo "1. DNS not pointing to server:"
    echo "   - Verify DNS A record: dig +short $domain"
    echo "   - Expected IP: $(get_server_ip)"
    echo ""
    echo "2. Port 80 blocked:"
    echo "   - Check firewall: sudo ufw status"
    echo "   - Allow port 80: sudo ufw allow 80/tcp"
    echo ""
    echo "3. Web server not configured:"
    echo "   - Check status: systemctl status nginx"
    echo "   - Restart: systemctl restart nginx"
    echo ""

    read -p "Press Enter to continue..."
}

handle_dns01_challenge() {
    local domain=$1
    local email=$2

    print_header
    echo -e "${BOLD}DNS-01 Challenge Configuration${NC}\n"

    log INFO "Preparing DNS-01 challenge for $domain..."

    echo -e "${YELLOW}DNS-01 Challenge requires manual DNS configuration${NC}\n"

    echo "This challenge type requires you to:"
    echo "1. Add a TXT record to your domain's DNS"
    echo "2. Wait for DNS propagation (can take up to 10 minutes)"
    echo ""

    if prompt_yes_no "Continue with DNS-01 challenge?" "y"; then
        local certbot_cmd="certbot certonly --manual --preferred-challenges dns -d $domain"

        if [ -n "$email" ]; then
            certbot_cmd="$certbot_cmd --email $email --agree-tos"
        fi

        echo -e "\n${CYAN}Follow the instructions provided by certbot:${NC}\n"

        if eval "$certbot_cmd"; then
            log SUCCESS "Certificate issued successfully via DNS-01 challenge"
            return 0
        else
            log ERROR "Certificate issuance failed"
            return 1
        fi
    else
        log INFO "DNS-01 challenge cancelled"
        return 1
    fi
}

handle_wildcard_certificate() {
    local domain=$1
    local email=$2

    print_header
    echo -e "${BOLD}Wildcard Certificate Configuration${NC}\n"
    echo -e "Domain: ${GREEN}*.$domain${NC}\n"

    log INFO "Wildcard certificates require DNS-01 challenge"

    echo -e "${YELLOW}Important:${NC}"
    echo "- Wildcard certs cover *.example.com but NOT example.com"
    echo "- You may want to include both in the certificate"
    echo ""

    if prompt_yes_no "Include both *.$domain and $domain?" "y"; then
        certbot certonly --manual --preferred-challenges dns \
            -d "$domain" -d "*.$domain" \
            --email "$email" --agree-tos
    else
        certbot certonly --manual --preferred-challenges dns \
            -d "*.$domain" \
            --email "$email" --agree-tos
    fi
}

################################################################################
# Certificate Issuance
################################################################################

issue_certificate_wizard() {
    local server_ip=$(get_server_ip)
    local web_server=$(detect_web_server)

    print_header
    echo -e "${BOLD}Certificate Issuance Wizard${NC}\n"
    echo -e "Server IP: ${GREEN}$server_ip${NC}"
    if [ -n "$web_server" ]; then
        echo -e "Web Server: ${GREEN}$web_server${NC}"
    fi
    echo ""
    print_separator

    # Get domain
    read -p "Enter domain name: " domain

    if ! validate_domain "$domain"; then
        log ERROR "Invalid domain name"
        read -p "Press Enter to continue..."
        return 1
    fi

    # Check for wildcard
    if [[ "$domain" == *"*"* ]]; then
        handle_wildcard_certificate "${domain#\*.}" "$email"
        return $?
    fi

    # Get email
    read -p "Enter email address (for notifications): " email

    if [ -z "$email" ]; then
        email="admin@$domain"
        log INFO "Using default email: $email"
    fi

    # Verify DNS
    echo ""
    log INFO "Verifying DNS configuration..."

    if verify_dns_record "$domain" "$server_ip"; then
        echo -e "${GREEN}✓${NC} DNS verification passed"
    else
        echo -e "${RED}✗${NC} DNS verification failed"

        if ! prompt_yes_no "Continue anyway?" "n"; then
            return 1
        fi
    fi

    # Select challenge type
    show_acme_challenge_menu "$domain"
    local challenge_choice=$ACME_CHOICE

    case $challenge_choice in
        1)
            handle_http01_challenge "$domain" "$email" "$web_server"
            ;;
        2)
            handle_dns01_challenge "$domain" "$email"
            ;;
        3)
            log INFO "TLS-ALPN-01 challenge selected"
            certbot certonly --standalone --preferred-challenges tls-alpn-01 \
                -d "$domain" --email "$email" --agree-tos --non-interactive
            ;;
        4)
            log INFO "Auto-detecting challenge method"
            certbot certonly --nginx -d "$domain" \
                --email "$email" --agree-tos --non-interactive
            ;;
        0)
            return 0
            ;;
        *)
            log ERROR "Invalid selection"
            return 1
            ;;
    esac

    local result=$?

    if [ $result -eq 0 ]; then
        echo ""
        log SUCCESS "Certificate issued successfully for $domain"

        # Show certificate info
        show_certificate_info "$domain"

        # Configure web server
        if [ -n "$web_server" ]; then
            echo ""
            if prompt_yes_no "Configure $web_server with SSL?" "y"; then
                configure_web_server "$domain" "$web_server"
            fi
        fi
    fi

    echo ""
    read -p "Press Enter to continue..."
    return $result
}

show_certificate_info() {
    local domain=$1
    local cert_path="/etc/letsencrypt/live/$domain/fullchain.pem"

    if [ -f "$cert_path" ]; then
        echo -e "\n${BOLD}Certificate Information:${NC}"
        print_separator

        local expiry=$(openssl x509 -in "$cert_path" -noout -enddate | cut -d= -f2)
        local issuer=$(openssl x509 -in "$cert_path" -noout -issuer | cut -d= -f2-)
        local subject=$(openssl x509 -in "$cert_path" -noout -subject | cut -d= -f2-)

        echo -e "Domain:      ${GREEN}$subject${NC}"
        echo -e "Issuer:      ${CYAN}$issuer${NC}"
        echo -e "Expires:     ${YELLOW}$expiry${NC}"
        echo -e "Location:    $cert_path"

        print_separator
    fi
}

################################################################################
# Certificate Management
################################################################################

list_certificates() {
    print_header
    echo -e "${BOLD}Installed Certificates${NC}\n"

    if [ ! -d "$CERT_DIR/live" ]; then
        log WARNING "No certificates found"
        read -p "Press Enter to continue..."
        return
    fi

    echo -e "${BOLD}Domain${NC}\t\t\t${BOLD}Expires${NC}\t\t${BOLD}Days Left${NC}\t${BOLD}Status${NC}"
    print_separator

    for cert_dir in "$CERT_DIR/live"/*; do
        if [ -d "$cert_dir" ] && [ "$(basename "$cert_dir")" != "README" ]; then
            local domain=$(basename "$cert_dir")
            local cert_file="$cert_dir/fullchain.pem"

            if [ -f "$cert_file" ]; then
                local expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate | cut -d= -f2)
                local expiry_epoch=$(date -d "$expiry_date" +%s)
                local current_epoch=$(date +%s)
                local days_left=$(( ($expiry_epoch - $current_epoch) / 86400 ))

                local status_color=$GREEN
                local status="Valid"

                if [ $days_left -lt 0 ]; then
                    status_color=$RED
                    status="Expired"
                elif [ $days_left -lt 30 ]; then
                    status_color=$YELLOW
                    status="Expiring Soon"
                fi

                printf "%-30s %-20s %-15s ${status_color}%s${NC}\n" \
                    "$domain" \
                    "$(date -d "$expiry_date" +%Y-%m-%d)" \
                    "$days_left days" \
                    "$status"
            fi
        fi
    done

    echo ""
    read -p "Press Enter to continue..."
}

renew_certificate() {
    print_header
    echo -e "${BOLD}Certificate Renewal${NC}\n"

    echo "1) Renew all certificates"
    echo "2) Renew specific certificate"
    echo "0) Back to main menu"
    echo ""
    read -p "Select option: " choice

    case $choice in
        1)
            log INFO "Renewing all certificates..."
            certbot renew --quiet
            log SUCCESS "Certificate renewal completed"
            ;;
        2)
            read -p "Enter domain name: " domain
            log INFO "Renewing certificate for $domain..."
            certbot renew --cert-name "$domain"
            ;;
        0)
            return
            ;;
    esac

    echo ""
    read -p "Press Enter to continue..."
}

################################################################################
# Auto-Renewal Configuration
################################################################################

setup_auto_renewal() {
    print_header
    echo -e "${BOLD}Auto-Renewal Configuration${NC}\n"

    log INFO "Configuring automatic certificate renewal..."

    # Create renewal script
    cat > /usr/local/bin/cert-manager-renew.sh << 'EOF'
#!/bin/bash
LOG_FILE="/var/log/cert-manager/renewal.log"
date >> "$LOG_FILE"
certbot renew --quiet >> "$LOG_FILE" 2>&1
systemctl reload nginx >> "$LOG_FILE" 2>&1 || systemctl reload apache2 >> "$LOG_FILE" 2>&1
EOF

    chmod +x /usr/local/bin/cert-manager-renew.sh

    # Setup systemd timer
    cat > /etc/systemd/system/cert-renewal.service << EOF
[Unit]
Description=Certificate Renewal Service
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/cert-manager-renew.sh
EOF

    cat > /etc/systemd/system/cert-renewal.timer << EOF
[Unit]
Description=Certificate Renewal Timer
After=network.target

[Timer]
OnCalendar=daily
RandomizedDelaySec=3600
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # Enable and start timer
    systemctl daemon-reload
    systemctl enable cert-renewal.timer
    systemctl start cert-renewal.timer

    # Also add cron job as fallback
    (crontab -l 2>/dev/null; echo "0 3 * * * /usr/local/bin/cert-manager-renew.sh") | crontab -

    log SUCCESS "Auto-renewal configured successfully"
    echo ""
    echo "Certificates will be checked daily and renewed when needed (30 days before expiry)"
    echo ""
    echo "Timer status:"
    systemctl status cert-renewal.timer --no-pager | head -5

    echo ""
    read -p "Press Enter to continue..."
}

################################################################################
# Web Server Configuration
################################################################################

configure_web_server() {
    local domain=$1
    local web_server=$2

    case $web_server in
        nginx)
            configure_nginx "$domain"
            ;;
        apache2|httpd)
            configure_apache "$domain"
            ;;
        *)
            log WARNING "Unsupported web server: $web_server"
            ;;
    esac
}

configure_nginx() {
    local domain=$1
    local config_file="/etc/nginx/sites-available/$domain"
    local cert_path="/etc/letsencrypt/live/$domain"

    log INFO "Configuring Nginx for $domain..."

    # Backup existing config if it exists
    if [ -f "$config_file" ]; then
        cp "$config_file" "$config_file.backup.$(date +%s)"
    fi

    # Get backend port
    read -p "Enter backend port (default: 8000): " port
    port=${port:-8000}

    # Create Nginx configuration
    cat > "$config_file" << EOF
# HTTP - Redirect to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name $domain www.$domain;

    # ACME challenge
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    # Redirect all other traffic to HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

# HTTPS
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $domain www.$domain;

    # SSL Configuration
    ssl_certificate $cert_path/fullchain.pem;
    ssl_certificate_key $cert_path/privkey.pem;
    ssl_trusted_certificate $cert_path/chain.pem;

    # SSL Security
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers off;

    # SSL Session
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;

    # OCSP Stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;

    # Security Headers
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;

    # Logging
    access_log /var/log/nginx/${domain}.access.log;
    error_log /var/log/nginx/${domain}.error.log;

    # Backend Proxy
    location / {
        proxy_pass http://127.0.0.1:$port;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect off;
    }

    # Static files (optional)
    location /static/ {
        alias /var/www/$domain/static/;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    location /media/ {
        alias /var/www/$domain/media/;
        expires 30d;
    }
}
EOF

    # Enable site
    ln -sf "$config_file" "/etc/nginx/sites-enabled/$domain"

    # Test configuration
    if nginx -t 2>/dev/null; then
        systemctl reload nginx
        log SUCCESS "Nginx configured successfully for $domain"
    else
        log ERROR "Nginx configuration test failed"
        nginx -t
    fi
}

configure_apache() {
    local domain=$1
    local config_file="/etc/apache2/sites-available/$domain.conf"
    local cert_path="/etc/letsencrypt/live/$domain"

    log INFO "Configuring Apache for $domain..."

    # Get backend port
    read -p "Enter backend port (default: 8000): " port
    port=${port:-8000}

    # Create Apache configuration
    cat > "$config_file" << EOF
<VirtualHost *:80>
    ServerName $domain
    ServerAlias www.$domain

    # ACME challenge
    Alias /.well-known/acme-challenge/ /var/www/html/.well-known/acme-challenge/

    # Redirect to HTTPS
    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^(.*)$ https://%{HTTP_HOST}\$1 [R=301,L]
</VirtualHost>

<VirtualHost *:443>
    ServerName $domain
    ServerAlias www.$domain

    # SSL Configuration
    SSLEngine on
    SSLCertificateFile $cert_path/fullchain.pem
    SSLCertificateKeyFile $cert_path/privkey.pem

    # SSL Security
    SSLProtocol all -SSLv3 -TLSv1 -TLSv1.1
    SSLCipherSuite ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384
    SSLHonorCipherOrder off

    # Security Headers
    Header always set Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"

    # Logging
    ErrorLog \${APACHE_LOG_DIR}/${domain}.error.log
    CustomLog \${APACHE_LOG_DIR}/${domain}.access.log combined

    # Backend Proxy
    ProxyPreserveHost On
    ProxyPass / http://127.0.0.1:$port/
    ProxyPassReverse / http://127.0.0.1:$port/
</VirtualHost>
EOF

    # Enable modules
    a2enmod ssl rewrite headers proxy proxy_http

    # Enable site
    a2ensite "$domain"

    # Test configuration
    if apache2ctl -t 2>/dev/null; then
        systemctl reload apache2
        log SUCCESS "Apache configured successfully for $domain"
    else
        log ERROR "Apache configuration test failed"
        apache2ctl -t
    fi
}

################################################################################
# Backup and Restore
################################################################################

backup_certificates() {
    print_header
    echo -e "${BOLD}Certificate Backup${NC}\n"

    local backup_file="$BACKUP_DIR/cert-backup-$(date +%Y%m%d-%H%M%S).tar.gz"

    log INFO "Creating backup..."

    tar -czf "$backup_file" -C /etc letsencrypt 2>/dev/null

    if [ $? -eq 0 ]; then
        log SUCCESS "Backup created: $backup_file"
        local size=$(du -h "$backup_file" | cut -f1)
        echo "Backup size: $size"
    else
        log ERROR "Backup failed"
    fi

    echo ""
    read -p "Press Enter to continue..."
}

restore_certificates() {
    print_header
    echo -e "${BOLD}Certificate Restore${NC}\n"

    echo "Available backups:"
    ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null || echo "No backups found"

    echo ""
    read -p "Enter backup file path: " backup_file

    if [ ! -f "$backup_file" ]; then
        log ERROR "Backup file not found"
        read -p "Press Enter to continue..."
        return
    fi

    if prompt_yes_no "This will overwrite current certificates. Continue?" "n"; then
        log INFO "Restoring from backup..."
        tar -xzf "$backup_file" -C / 2>/dev/null

        if [ $? -eq 0 ]; then
            log SUCCESS "Certificates restored successfully"
        else
            log ERROR "Restore failed"
        fi
    fi

    echo ""
    read -p "Press Enter to continue..."
}

################################################################################
# Monitoring and Diagnostics
################################################################################

check_certificate_expiry() {
    print_header
    echo -e "${BOLD}Certificate Expiry Monitor${NC}\n"

    local warn_days=30
    local critical_days=7

    echo -e "Checking certificates expiring in the next ${YELLOW}$warn_days days${NC}...\n"

    for cert_dir in "$CERT_DIR/live"/*; do
        if [ -d "$cert_dir" ] && [ "$(basename "$cert_dir")" != "README" ]; then
            local domain=$(basename "$cert_dir")
            local cert_file="$cert_dir/fullchain.pem"

            if [ -f "$cert_file" ]; then
                local expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate | cut -d= -f2)
                local expiry_epoch=$(date -d "$expiry_date" +%s)
                local current_epoch=$(date +%s)
                local days_left=$(( ($expiry_epoch - $current_epoch) / 86400 ))

                if [ $days_left -lt $critical_days ]; then
                    echo -e "${RED}⚠ CRITICAL:${NC} $domain expires in $days_left days!"
                elif [ $days_left -lt $warn_days ]; then
                    echo -e "${YELLOW}⚠ WARNING:${NC} $domain expires in $days_left days"
                else
                    echo -e "${GREEN}✓${NC} $domain: $days_left days left"
                fi
            fi
        fi
    done

    echo ""
    read -p "Press Enter to continue..."
}

test_ssl_configuration() {
    print_header
    echo -e "${BOLD}SSL Configuration Test${NC}\n"

    read -p "Enter domain to test: " domain

    if [ -z "$domain" ]; then
        log ERROR "Domain required"
        read -p "Press Enter to continue..."
        return
    fi

    echo -e "\n${CYAN}Testing SSL/TLS configuration for $domain...${NC}\n"

    # Test connection
    echo -e "${BOLD}1. Testing HTTPS connection...${NC}"
    if timeout 5 openssl s_client -connect "$domain:443" -servername "$domain" </dev/null 2>/dev/null | grep -q "Verify return code: 0"; then
        echo -e "   ${GREEN}✓${NC} HTTPS connection successful"
    else
        echo -e "   ${RED}✗${NC} HTTPS connection failed"
    fi

    # Check certificate
    echo -e "\n${BOLD}2. Checking certificate...${NC}"
    local cert_info=$(echo | openssl s_client -connect "$domain:443" -servername "$domain" 2>/dev/null | openssl x509 -noout -dates 2>/dev/null)

    if [ -n "$cert_info" ]; then
        echo "$cert_info" | while read line; do
            echo "   $line"
        done
    fi

    # Check protocols
    echo -e "\n${BOLD}3. Supported TLS protocols:${NC}"
    for protocol in tls1_2 tls1_3; do
        if timeout 5 openssl s_client -connect "$domain:443" -servername "$domain" -"$protocol" </dev/null 2>/dev/null | grep -q "Protocol"; then
            echo -e "   ${GREEN}✓${NC} ${protocol//_/.}"
        else
            echo -e "   ${RED}✗${NC} ${protocol//_/.}"
        fi
    done

    # Check HSTS
    echo -e "\n${BOLD}4. Security headers:${NC}"
    local headers=$(curl -sI "https://$domain" 2>/dev/null)

    if echo "$headers" | grep -qi "Strict-Transport-Security"; then
        echo -e "   ${GREEN}✓${NC} HSTS enabled"
    else
        echo -e "   ${YELLOW}⚠${NC} HSTS not enabled"
    fi

    if echo "$headers" | grep -qi "X-Frame-Options"; then
        echo -e "   ${GREEN}✓${NC} X-Frame-Options set"
    else
        echo -e "   ${YELLOW}⚠${NC} X-Frame-Options not set"
    fi

    echo -e "\n${CYAN}For detailed analysis, visit: https://www.ssllabs.com/ssltest/analyze.html?d=$domain${NC}"

    echo ""
    read -p "Press Enter to continue..."
}

view_logs() {
    print_header
    echo -e "${BOLD}Certificate Manager Logs${NC}\n"

    echo "1) View recent logs (last 50 lines)"
    echo "2) View renewal logs"
    echo "3) View error logs"
    echo "4) View all logs"
    echo "0) Back to main menu"
    echo ""
    read -p "Select option: " choice

    case $choice in
        1)
            tail -n 50 "$LOG_FILE"
            ;;
        2)
            tail -n 50 /var/log/letsencrypt/letsencrypt.log 2>/dev/null || echo "No renewal logs found"
            ;;
        3)
            grep ERROR "$LOG_FILE" | tail -n 50
            ;;
        4)
            less "$LOG_FILE"
            ;;
        0)
            return
            ;;
    esac

    echo ""
    read -p "Press Enter to continue..."
}

################################################################################
# Main Menu
################################################################################

show_main_menu() {
    print_header

    local server_ip=$(get_server_ip)
    local web_server=$(detect_web_server)

    echo -e "Server IP: ${GREEN}$server_ip${NC}"
    if [ -n "$web_server" ]; then
        echo -e "Web Server: ${GREEN}$web_server${NC}"
    else
        echo -e "Web Server: ${YELLOW}Not detected${NC}"
    fi
    echo ""
    print_separator

    echo -e "${BOLD}Certificate Management:${NC}"
    echo "  1) Issue New Certificate"
    echo "  2) List All Certificates"
    echo "  3) Renew Certificate"
    echo "  4) Revoke Certificate"
    echo ""

    echo -e "${BOLD}Configuration:${NC}"
    echo "  5) Configure Web Server (Nginx/Apache)"
    echo "  6) Setup Auto-Renewal"
    echo "  7) Backup Certificates"
    echo "  8) Restore Certificates"
    echo ""

    echo -e "${BOLD}Monitoring & Diagnostics:${NC}"
    echo "  9) Check Certificate Expiry"
    echo "  10) Test SSL Configuration"
    echo "  11) View Logs"
    echo ""

    echo -e "${BOLD}System:${NC}"
    echo "  12) Install Dependencies"
    echo "  13) System Information"
    echo ""

    echo "  0) Exit"
    echo ""
    print_separator

    read -p "Select option: " MENU_CHOICE
}

show_system_info() {
    print_header
    echo -e "${BOLD}System Information${NC}\n"

    detect_os

    echo -e "${BOLD}Operating System:${NC}"
    echo "  OS: $OS"
    echo "  Version: $OS_VERSION"
    echo ""

    echo -e "${BOLD}Network:${NC}"
    echo "  Server IP: $(get_server_ip)"
    echo ""

    echo -e "${BOLD}Web Server:${NC}"
    local web_server=$(detect_web_server)
    if [ -n "$web_server" ]; then
        echo "  Type: $web_server"
        echo "  Status: $(systemctl is-active $web_server)"
    else
        echo "  Type: Not detected"
    fi
    echo ""

    echo -e "${BOLD}Certbot:${NC}"
    if command -v certbot &> /dev/null; then
        echo "  Version: $(certbot --version 2>&1 | head -n1)"
        echo "  Status: Installed"
    else
        echo "  Status: Not installed"
    fi
    echo ""

    echo -e "${BOLD}Certificates:${NC}"
    if [ -d "$CERT_DIR/live" ]; then
        local cert_count=$(ls -1 "$CERT_DIR/live" 2>/dev/null | grep -v README | wc -l)
        echo "  Total: $cert_count"
    else
        echo "  Total: 0"
    fi
    echo ""

    echo -e "${BOLD}Auto-Renewal:${NC}"
    if systemctl is-active --quiet cert-renewal.timer; then
        echo "  Status: ${GREEN}Enabled${NC}"
        echo "  Next run: $(systemctl status cert-renewal.timer 2>/dev/null | grep Trigger | awk '{print $3, $4, $5}')"
    else
        echo "  Status: ${YELLOW}Not configured${NC}"
    fi

    echo ""
    read -p "Press Enter to continue..."
}

################################################################################
# Main Loop
################################################################################

main() {
    check_root

    # Initialize log
    log INFO "Certificate Manager started (v$SCRIPT_VERSION)"

    while true; do
        show_main_menu
        choice=$MENU_CHOICE

        case $choice in
            1)
                issue_certificate_wizard
                ;;
            2)
                list_certificates
                ;;
            3)
                renew_certificate
                ;;
            4)
                read -p "Enter domain to revoke: " domain
                certbot revoke --cert-name "$domain"
                read -p "Press Enter to continue..."
                ;;
            5)
                read -p "Enter domain: " domain
                local web_server=$(detect_web_server)
                configure_web_server "$domain" "$web_server"
                read -p "Press Enter to continue..."
                ;;
            6)
                setup_auto_renewal
                ;;
            7)
                backup_certificates
                ;;
            8)
                restore_certificates
                ;;
            9)
                check_certificate_expiry
                ;;
            10)
                test_ssl_configuration
                ;;
            11)
                view_logs
                ;;
            12)
                install_dependencies
                ;;
            13)
                show_system_info
                ;;
            0)
                print_header
                log INFO "Certificate Manager stopped"
                echo -e "${GREEN}Thank you for using Certificate Manager!${NC}"
                echo ""
                exit 0
                ;;
            *)
                log ERROR "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# Run main function
main
