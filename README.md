# Advanced Server Management Scripts

Professional-grade scripts for SSL/TLS certificate management, web server configuration, and Django deployment.

---

## 🔐 Advanced SSL/TLS Certificate Manager

**Production-ready certificate management system with Let's Encrypt integration**

### Features

- ✅ **Interactive Menu Interface** - User-friendly terminal UI with color-coded outputs
- ✅ **Multiple ACME Challenge Support**
  - HTTP-01 (Standard web-based validation)
  - DNS-01 (For wildcard certificates)
  - TLS-ALPN-01 (Advanced TLS validation)
- ✅ **Smart Domain Verification** - Automatic DNS record checking and validation
- ✅ **Automated Renewal** - Set-it-and-forget-it certificate renewal with systemd timers
- ✅ **Multi-CA Support** - Let's Encrypt, ZeroSSL, and other ACME providers
- ✅ **Web Server Auto-Configuration** - Nginx and Apache with security best practices
- ✅ **Certificate Monitoring** - Expiry tracking and alerts
- ✅ **Backup & Restore** - Automated certificate backup system
- ✅ **SSL Testing Tools** - Built-in configuration validation
- ✅ **Comprehensive Logging** - Detailed audit trail

### Quick Start

```bash
wget -q --no-check-certificate https://raw.githubusercontent.com/pgwiz/scripts/refs/heads/master/cert-manager.sh -O cm.sh && sudo bash cm.sh
```

### Installation Steps

#### Option 1: One-Line Installation (Recommended)

```bash
wget -q --no-check-certificate https://raw.githubusercontent.com/pgwiz/scripts/refs/heads/master/cert-manager.sh -O cm.sh && sudo bash cm.sh
```

#### Option 2: Manual Installation

```bash
wget -q --no-check-certificate https://raw.githubusercontent.com/pgwiz/scripts/refs/heads/master/cert-manager.sh -O cm.sh
chmod +x cm.sh
sudo ./cm.sh
```

#### Option 3: System-Wide Installation

```bash
sudo wget -q --no-check-certificate https://raw.githubusercontent.com/pgwiz/scripts/refs/heads/master/cert-manager.sh -O /usr/local/bin/cm && sudo chmod +x /usr/local/bin/cm
```

Then run from anywhere:

```bash
sudo cm
```

---

## 📋 Certificate Manager Usage Guide

### First-Time Setup

1. **Install Dependencies** (Automatic on first run)
   - The script will detect your OS and install required packages
   - Includes: certbot, nginx/apache plugins, DNS tools

2. **Issue Your First Certificate**
   - Select option `1) Issue New Certificate`
   - Enter your domain name
   - The script will:
     - Verify DNS is pointing to your server
     - Guide you through ACME challenge selection
     - Issue the certificate
     - Optionally configure your web server

### ACME Challenge Guide

#### HTTP-01 Challenge (Recommended for most users)

**Best for:**
- Single domain certificates
- Servers with direct internet access
- Port 80 is accessible

**Requirements:**
- Domain must point to your server IP
- Port 80 must be open in firewall
- Web server installed (or script will install Nginx)

**Example:**
```
Domain: example.com
DNS A Record: example.com → 192.0.2.1 (your server IP)
Firewall: Allow port 80 and 443
```

#### DNS-01 Challenge (For wildcard certificates)

**Best for:**
- Wildcard certificates (*.example.com)
- Servers behind firewalls
- Multiple subdomains

**Requirements:**
- Access to DNS management
- Ability to add TXT records

**Example:**
```
Domain: *.example.com
Add TXT record: _acme-challenge.example.com → "random-verification-string"
```

**Wildcard Certificate Example:**
```bash
# Covers both example.com and *.example.com
Domains: example.com, *.example.com
Challenge: DNS-01 (required for wildcards)
```

#### TLS-ALPN-01 Challenge (Advanced)

**Best for:**
- Port 80 blocked but 443 available
- Advanced network configurations

**Requirements:**
- Port 443 accessible
- TLS-ALPN extension support

### Menu Options Explained

#### 1️⃣ Certificate Management

**Issue New Certificate**
- Interactive wizard for certificate issuance
- DNS verification before attempting
- Challenge method selection
- Automatic web server configuration

**List All Certificates**
- View all installed certificates
- Check expiry dates
- Status indicators (Valid, Expiring Soon, Expired)

**Renew Certificate**
- Manually renew specific or all certificates
- Typically needed only for testing (auto-renewal handles production)

**Revoke Certificate**
- Revoke compromised certificates
- Removes certificate from Let's Encrypt

#### 2️⃣ Configuration

**Configure Web Server**
- Generates optimal SSL configuration
- Includes security headers (HSTS, X-Frame-Options)
- HTTP to HTTPS redirect
- OCSP stapling
- Modern TLS protocols only (TLS 1.2, 1.3)

**Setup Auto-Renewal**
- Creates systemd timer for daily checks
- Adds cron job as fallback
- Renewals trigger 30 days before expiry
- Automatic web server reload after renewal

**Backup Certificates**
- Creates compressed backup of all certificates
- Stored in `/var/backups/cert-manager/`
- Includes private keys and certificate chains

**Restore Certificates**
- Restore from previous backup
- Useful for disaster recovery or server migration

#### 3️⃣ Monitoring & Diagnostics

**Check Certificate Expiry**
- Lists all certificates with days until expiry
- Color-coded warnings:
  - 🔴 Red: < 7 days (Critical)
  - 🟡 Yellow: < 30 days (Warning)
  - 🟢 Green: > 30 days (OK)

**Test SSL Configuration**
- Validates HTTPS connection
- Checks certificate validity
- Tests TLS protocol support
- Verifies security headers
- Provides SSL Labs testing link

**View Logs**
- Recent activity logs
- Renewal attempt logs
- Error logs for troubleshooting

---

## 🚀 Common Scenarios

### Scenario 1: Single Domain with Django

```bash
# Step 1: Issue certificate
sudo cm
# Select: 1) Issue New Certificate
# Enter domain: example.com
# Enter email: admin@example.com
# Select challenge: 1) HTTP-01
# Configure web server: Yes

# Step 2: Setup auto-renewal
# Select: 6) Setup Auto-Renewal
```

### Scenario 2: Wildcard Certificate

```bash
sudo cm
# Select: 1) Issue New Certificate
# Enter domain: *.example.com
# Email: admin@example.com
# Challenge: DNS-01 (automatically selected)
# Follow DNS TXT record instructions
# Wait for DNS propagation
```

### Scenario 3: Multiple Domains

```bash
# Run the wizard for each domain, or use certbot directly:
certbot certonly --nginx -d example.com -d www.example.com -d api.example.com
```

### Scenario 4: Migration from Existing Server

```bash
# On old server — create backup
sudo cm
# Select: 7) Backup Certificates

# Copy backup to new server
scp /var/backups/cert-manager/cert-backup-*.tar.gz newserver:/tmp/

# On new server — restore
sudo cm
# Select: 8) Restore Certificates
# Enter backup path: /tmp/cert-backup-*.tar.gz
```

---

## 🔧 Troubleshooting Guide

### DNS Verification Failed

**Problem:** "DNS verification failed: domain points to different IP"

**Solutions:**
1. Check DNS propagation:
   ```bash
   dig +short example.com
   nslookup example.com
   ```
2. Wait for DNS propagation (up to 48 hours)
3. Verify your domain registrar's DNS settings
4. Use online tools: https://www.whatsmydns.net/

### HTTP-01 Challenge Failed

**Problem:** "Challenge validation failed"

1. **Port 80 blocked:**
   ```bash
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   ```

2. **Web server not running:**
   ```bash
   sudo systemctl start nginx
   ```

3. **Incorrect web server configuration:**
   ```bash
   sudo nginx -t
   sudo tail -f /var/log/nginx/error.log
   ```

4. **Domain not pointing to server:**
   ```bash
   curl -v http://example.com/.well-known/acme-challenge/test
   ```

### DNS-01 Challenge Failed

**Problem:** "DNS TXT record not found"

1. **Verify TXT record:**
   ```bash
   dig TXT _acme-challenge.example.com
   ```
2. Wait for DNS propagation (5–10 minutes; CloudFlare is typically 1–2 minutes)

### Certificate Not Renewing

**Problem:** Auto-renewal not working

1. **Check timer status:**
   ```bash
   sudo systemctl status cert-renewal.timer
   ```

2. **Test renewal manually:**
   ```bash
   sudo certbot renew --dry-run
   ```

3. **Check renewal logs:**
   ```bash
   sudo tail -f /var/log/letsencrypt/letsencrypt.log
   sudo tail -f /var/log/cert-manager/renewal.log
   ```

4. **Re-setup auto-renewal:**
   ```bash
   sudo cm
   # Select: 6) Setup Auto-Renewal
   ```

### Web Server Configuration Issues

**Problem:** Nginx/Apache not loading SSL config

1. **Test configuration:**
   ```bash
   sudo nginx -t
   sudo apache2ctl configtest
   ```

2. **Check if site is enabled:**
   ```bash
   ls -la /etc/nginx/sites-enabled/
   a2ensite example.com
   ```

3. **Reload web server:**
   ```bash
   sudo systemctl reload nginx
   sudo systemctl reload apache2
   ```

---

## 📊 Web Server Configuration Details

### Nginx Configuration (Generated by Script)

The script generates production-ready Nginx configurations with:

- **HTTP to HTTPS redirect**
- **Modern TLS protocols** (TLS 1.2, 1.3)
- **Strong cipher suites**
- **OCSP stapling**
- **Security headers:** HSTS, X-Frame-Options, X-Content-Type-Options, X-XSS-Protection, Referrer-Policy
- **Optimized SSL session caching**
- **Backend proxy configuration**
- **Static file serving with caching**

**Config location:** `/etc/nginx/sites-available/yourdomain.com`

### Apache Configuration (Generated by Script)

Includes SSL/TLS encryption, HTTP to HTTPS redirect, security headers, proxy configuration, and logging.

**Config location:** `/etc/apache2/sites-available/yourdomain.com.conf`

---

## 🛡️ Security Best Practices

### 1. Regular Updates

```bash
sudo apt update && sudo apt upgrade certbot
sudo wget -q --no-check-certificate https://raw.githubusercontent.com/pgwiz/scripts/refs/heads/master/cert-manager.sh -O /usr/local/bin/cm
```

### 2. Monitor Certificate Expiry

```bash
sudo cm
# Select: 9) Check Certificate Expiry
```

### 3. Backup Certificates

```bash
sudo cm
# Select: 7) Backup Certificates

# Store backups off-server
scp /var/backups/cert-manager/*.tar.gz backup-server:/backups/
```

### 4. Test SSL Configuration

```bash
sudo cm
# Select: 10) Test SSL Configuration
# Or: https://www.ssllabs.com/ssltest/
```

### 5. Limit Certificate Requests

- Let's Encrypt rate limits: 50 certificates per domain per week
- Use `--staging` flag for testing (script handles this automatically)

### 6. Secure Private Keys

```bash
# Should be: -rw-r----- root root
ls -la /etc/letsencrypt/live/*/privkey.pem
```

---

## 📁 File Locations

### Certificates

```
/etc/letsencrypt/
├── live/
│   └── example.com/
│       ├── fullchain.pem    # Full certificate chain
│       ├── privkey.pem      # Private key
│       ├── cert.pem         # Domain certificate
│       └── chain.pem        # Intermediate certificates
├── archive/                 # Certificate history
└── renewal/                 # Renewal configuration
```

### Script Configuration

```
/etc/cert-manager/           # Configuration files
/var/log/cert-manager/       # Logs
/var/backups/cert-manager/   # Backups
```

### Web Server Configurations

```
/etc/nginx/sites-available/       # Nginx available sites
/etc/nginx/sites-enabled/         # Nginx enabled sites
/etc/apache2/sites-available/     # Apache available sites
/etc/apache2/sites-enabled/       # Apache enabled sites
```

---

## 🐧 Django Deployment Scripts

### Ubuntu — Django with Gunicorn

```bash
wget -q --no-check-certificate https://raw.githubusercontent.com/pgwiz/scripts/refs/heads/master/django_scripts/djang_one.sh -O dj.sh && bash dj.sh
```

**Features:** Automated Django setup, Gunicorn configuration, systemd service creation, Nginx configuration, static file serving.

### Debian — Django with Gunicorn

```bash
wget -q --no-check-certificate https://raw.githubusercontent.com/pgwiz/scripts/refs/heads/master/django_scripts/django_one_debian.sh -O dj.sh && bash dj.sh
```

### Manual SSL Installation (Legacy)

> **Note:** Use the Advanced Certificate Manager instead for better features.

```bash
wget -q --no-check-certificate https://raw.githubusercontent.com/pgwiz/scripts/refs/heads/master/django_scripts/domain_ssl.sh -O ssl.sh && bash ssl.sh
```

### Git Pull Script

```bash
wget -q --no-check-certificate https://raw.githubusercontent.com/pgwiz/scripts/refs/heads/master/django_scripts/git_pull.sh -O gp.sh && bash gp.sh
```

---

## 🔄 Complete Deployment Workflow

### Full Stack Deployment (Django + SSL + Auto-Renewal)

```bash
# Step 1: Deploy Django application (Ubuntu)
wget -q --no-check-certificate https://raw.githubusercontent.com/pgwiz/scripts/refs/heads/master/django_scripts/djang_one.sh -O dj.sh && bash dj.sh

# Step 2: Install and configure SSL
wget -q --no-check-certificate https://raw.githubusercontent.com/pgwiz/scripts/refs/heads/master/cert-manager.sh -O cm.sh && sudo bash cm.sh
# In the Certificate Manager:
# 1) Issue New Certificate → enter domain → HTTP-01 → configure web server: Yes
# 6) Setup Auto-Renewal
# 0) Exit

# Step 3: Verify deployment
curl -I https://yourdomain.com

# Step 4: Test SSL
# https://www.ssllabs.com/ssltest/analyze.html?d=yourdomain.com
```

---

## 🆘 Support & Additional Resources

### Logs

```bash
sudo tail -f /var/log/cert-manager/cert-manager.log
sudo tail -f /var/log/letsencrypt/letsencrypt.log
sudo tail -f /var/log/nginx/error.log
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/apache2/error.log
```

### Useful Commands

```bash
sudo certbot certificates          # List all certificates
sudo certbot renew --dry-run       # Test renewal
sudo certbot revoke --cert-name example.com
sudo certbot delete --cert-name example.com
sudo systemctl status nginx
sudo systemctl reload nginx
sudo systemctl reload apache2
```

### Resources

- Let's Encrypt Docs: https://letsencrypt.org/docs/
- Rate Limits: https://letsencrypt.org/docs/rate-limits/
- Challenge Types: https://letsencrypt.org/docs/challenge-types/
- SSL Labs: https://www.ssllabs.com/ssltest/
- SSL Checker: https://www.sslshopper.com/ssl-checker.html

---

## 📝 Version History

### v2.0.0 - Advanced Certificate Manager
- Complete rewrite with modular architecture
- Interactive menu system
- Multiple ACME challenge support
- Automated renewal with systemd
- Web server auto-configuration
- Certificate monitoring and diagnostics
- Backup and restore functionality
- Comprehensive logging

### v1.0.0 - Basic SSL Scripts
- Simple SSL installation
- Django deployment scripts
- Basic Nginx configuration

---

## 📄 License

MIT License — Free to use and modify

## 🤝 Contributing

Found a bug or want to contribute? Issues and pull requests welcome!

Repository: https://github.com/pgwiz/scripts

---

## ⚡ Quick Reference

```bash
# Install & run Certificate Manager
wget -q --no-check-certificate https://raw.githubusercontent.com/pgwiz/scripts/refs/heads/master/cert-manager.sh -O cm.sh && sudo bash cm.sh

# Run (after system-wide install)
sudo cm

# Test renewal
sudo certbot renew --dry-run

# List certificates
sudo certbot certificates

# Check & reload nginx
sudo nginx -t && sudo systemctl reload nginx
```

---

**Need Help?** Check the troubleshooting section or view the logs for detailed error messages.

## 💾 Advanced RAM Disk Creator

**Professional-grade script for creating and managing tmpfs RAM disks**

### Features

- ✅ **Interactive Menu Interface** - Easy-to-use terminal UI for creating and managing disks
- ✅ **Size Validation & Safety Caps** - Prevents system crashes by validating requested size against available physical RAM
- ✅ **Persistence Management** - Automatically handles `fstab` or `systemd` entries for auto-mounting on boot
- ✅ **State Tracking** - Maintains a database of managed RAM disks for easy listing and removal
- ✅ **Dry-run Mode** - See what actions will be performed without actually executing them
- ✅ **JSON Output** - Machine-readable output for programmatic usage
- ✅ **Comprehensive Error Handling** - Validates inputs, mount points, and permissions gracefully

### Quick Start

```bash
wget -q --no-check-certificate https://raw.githubusercontent.com/pgwiz/scripts/refs/heads/master/ramdisk.sh -O ramdisk.sh && chmod +x ramdisk.sh
sudo ./memman.sh
```

### Command Line Usage

The script can be used interactively (by running without arguments) or via command line flags for automation.

**Create a RAM disk:**
```bash
sudo ./memman.sh ramdisk --create --size 1G --mount /mnt/fastcache --persist systemd
```

**List active managed RAM disks:**
```bash
./memman.sh ramdisk --list
```

**Remove a RAM disk (with cleanup):**
```bash
sudo ./memman.sh ramdisk --remove --mount /mnt/fastcache
```

### Configuration Options

You can customize defaults by creating a configuration file at `/etc/ramdisk-creator.conf`:

```bash
DEFAULT_SIZE="512M"
DEFAULT_MOUNT_PREFIX="/mnt/ramdisk"
SAFETY_CAP_PERCENT=50
DEFAULT_PERMS="1777"
DEFAULT_PERSIST="none"
```

## 💽 Advanced Swap & ZRAM Manager

**Professional-grade script for creating and managing swapfiles, swap partitions, and ZRAM devices**

### Features

- ✅ **Three Swap Backends** - Supports Swapfiles, Swap Partitions, and ZRAM (compressed in-RAM swap)
- ✅ **Intelligent Size Logic** - Calculates recommended swap sizes based on physical RAM
- ✅ **Btrfs Support** - Safely provisions swapfiles on Btrfs by disabling copy-on-write
- ✅ **ZRAM Persistence** - Integrates with systemd to re-create ZRAM swaps on boot
- ✅ **Safe Swap Removal** - Checks memory availability to ensure `swapoff` won't trigger OOM
- ✅ **Kernel Tuning Presets** - Offers predefined tunings (server, desktop, aggressive) for `swappiness` and related settings
- ✅ **Live Monitor Mode** - Built-in `watch` UI to monitor swap and RAM usage in real-time
- ✅ **Multi-Swap State Tracking** - Safely manage multiple layered swaps across your system

### Quick Start

```bash
wget -q --no-check-certificate https://raw.githubusercontent.com/pgwiz/scripts/refs/heads/master/swapman.sh -O swapman.sh && chmod +x swapman.sh
sudo ./memman.sh
```

### Command Line Usage

**Create a ZRAM device (recommended for low-memory servers):**
```bash
sudo ./memman.sh swap --create --backend zram --size 1G
```

**Create a traditional swapfile:**
```bash
sudo ./memman.sh swap --create --backend file --path /swapfile --size 2G
```

**Apply Server Kernel Tuning:**
```bash
sudo ./memman.sh swap --tune server
```

**Watch Swap Usage Live:**
```bash
./memman.sh swap --watch --interval 2
```

**List active managed swaps:**
```bash
./memman.sh swap --list
```

**Remove a swap (safely):**
```bash
sudo ./memman.sh swap --remove --path /swapfile
```
