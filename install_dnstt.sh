#!/bin/bash

# DNSTT Server Installation Script
# Port: 7894
# Created: February 2026

set -e

echo "======================================"
echo "DNSTT Server Installation Script"
echo "======================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}" 
   exit 1
fi

echo -e "${GREEN}Step 1: Updating system packages...${NC}"
apt update -y
apt install -y wget git screen ufw

echo ""
echo -e "${GREEN}Step 2: Installing Go...${NC}"
if ! command -v go &> /dev/null; then
    cd /tmp
    wget https://go.dev/dl/go1.21.6.linux-amd64.tar.gz
    tar -C /usr/local -xzf go1.21.6.linux-amd64.tar.gz
    echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
    export PATH=$PATH:/usr/local/go/bin
    source /etc/profile
    echo -e "${GREEN}Go installed successfully${NC}"
else
    echo -e "${YELLOW}Go already installed${NC}"
fi

go version

echo ""
echo -e "${GREEN}Step 3: Cloning and building DNSTT...${NC}"
cd /root
if [ -d "dnstt" ]; then
    echo -e "${YELLOW}DNSTT directory exists, removing...${NC}"
    rm -rf dnstt
fi

git clone https://www.bamsoftware.com/git/dnstt.git
cd dnstt/dnstt-server
go build

echo ""
echo -e "${GREEN}Step 4: Generating server keys...${NC}"
./dnstt-server -gen-key -privkey-file server.key -pubkey-file server.pub

echo ""
echo -e "${YELLOW}Your Public Key (save this for client configuration):${NC}"
cat server.pub
echo ""

# Prompt for domain
echo -e "${YELLOW}Enter your domain (e.g., example.com):${NC}"
read -p "Domain: " DOMAIN

if [ -z "$DOMAIN" ]; then
    echo -e "${RED}Domain cannot be empty!${NC}"
    exit 1
fi

TUNNEL_DOMAIN="t.$DOMAIN"
NS_DOMAIN="tns.$DOMAIN"

# Prompt for backend port
echo ""
echo -e "${YELLOW}Where should DNSTT forward traffic?${NC}"
echo "1) SSH (port 22)"
echo "2) SOCKS Proxy (port 1080)"
echo "3) Custom port"
read -p "Select option [1-3]: " BACKEND_OPTION

case $BACKEND_OPTION in
    1)
        BACKEND_PORT="22"
        ;;
    2)
        BACKEND_PORT="1080"
        ;;
    3)
        read -p "Enter custom port: " BACKEND_PORT
        ;;
    *)
        echo -e "${RED}Invalid option${NC}"
        exit 1
        ;;
esac

BACKEND="127.0.0.1:$BACKEND_PORT"

echo ""
echo -e "${GREEN}Step 5: Configuring firewall...${NC}"
ufw allow 7894/udp
ufw allow 22/tcp
ufw --force enable

echo ""
echo -e "${GREEN}Step 6: Creating systemd service...${NC}"
cat > /etc/systemd/system/dnstt.service << EOF
[Unit]
Description=DNSTT DNS Tunnel Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/dnstt/dnstt-server
ExecStart=/root/dnstt/dnstt-server/dnstt-server -udp :7894 -privkey-file /root/dnstt/dnstt-server/server.key $TUNNEL_DOMAIN $BACKEND
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable dnstt
systemctl start dnstt

echo ""
echo -e "${GREEN}Step 7: Checking service status...${NC}"
sleep 2
systemctl status dnstt --no-pager

echo ""
echo "======================================"
echo -e "${GREEN}Installation Complete!${NC}"
echo "======================================"
echo ""
echo -e "${YELLOW}Server Configuration:${NC}"
echo "  UDP Port: 7894"
echo "  Tunnel Domain: $TUNNEL_DOMAIN"
echo "  NS Domain: $NS_DOMAIN"
echo "  Backend: $BACKEND"
echo ""
echo -e "${YELLOW}DNS Records (Add these to your domain):${NC}"
echo "  Type  | Name              | Value"
echo "  ------|-------------------|------------------"
echo "  A     | $NS_DOMAIN | $(curl -s ifconfig.me)"
echo "  NS    | $TUNNEL_DOMAIN    | $NS_DOMAIN"
echo ""
echo -e "${YELLOW}Public Key (for client):${NC}"
cat /root/dnstt/dnstt-server/server.pub
echo ""
echo -e "${YELLOW}Client Settings:${NC}"
echo "  Server: $TUNNEL_DOMAIN"
echo "  Port: 7894"
echo "  Public Key: (see above)"
echo "  DoH Resolver: https://cloudflare-dns.com/dns-query"
echo ""
echo -e "${GREEN}Service Commands:${NC}"
echo "  Start:   systemctl start dnstt"
echo "  Stop:    systemctl stop dnstt"
echo "  Restart: systemctl restart dnstt"
echo "  Status:  systemctl status dnstt"
echo "  Logs:    journalctl -u dnstt -f"
echo ""
echo -e "${RED}Important: Wait 1-24 hours for DNS propagation!${NC}"
echo "======================================"
