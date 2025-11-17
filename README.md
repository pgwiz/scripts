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
# Download and run the certificate manager
wget --no-check-certificate https://raw.githubusercontent.com/pgwiz/scripts/refs/heads/master/cert-manager.sh -O cert-manager.sh && sudo bash cert-manager.sh
```

### Installation Steps

#### Option 1: One-Line Installation (Recommended)

```bash
# Download and execute directly
wget --no-check-certificate https://raw.githubusercontent.com/pgwiz/scripts/refs/heads/master/cert-manager.sh -O cert-manager.sh && sudo bash cert-manager.sh
```

#### Option 2: Manual Installation

```bash
# Download the script
wget --no-check-certificate https://raw.githubusercontent.com/pgwiz/scripts/refs/heads/master/cert-manager.sh -O cert-manager.sh

# Make it executable
chmod +x cert-manager.sh

# Run with sudo
sudo ./cert-manager.sh
```

#### Option 3: System-Wide Installation

```bash
# Download and install to /usr/local/bin
sudo wget --no-check-certificate https://raw.githubusercontent.com/pgwiz/scripts/refs/heads/master/cert-manager.sh -O /usr/local/bin/cert-manager

# Make executable
sudo chmod +x /usr/local/bin/cert-manager

# Run from anywhere
sudo cert-manager
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
You'll need to add a TXT record:
_acme-challenge.example.com → "random-verification-string"
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
sudo cert-manager
# Select: 1) Issue New Certificate
# Enter domain: example.com
# Enter email: admin@example.com
# Select challenge: 1) HTTP-01
# Configure web server: Yes

# Step 2: Setup auto-renewal
# Select: 6) Setup Auto-Renewal

# Done! Certificate will auto-renew.
```

### Scenario 2: Wildcard Certificate

```bash
# Step 1: Issue wildcard certificate
sudo cert-manager
# Select: 1) Issue New Certificate
# Enter domain: *.example.com
# Email: admin@example.com
# Challenge: DNS-01 (automatically selected)
# Follow DNS TXT record instructions
# Wait for DNS propagation
# Certificate issued for *.example.com
```

### Scenario 3: Multiple Domains

```bash
# Issue certificates for multiple domains
# Run the wizard for each domain:
# - example.com
# - api.example.com
# - admin.example.com

# Or use certbot directly for multiple domains:
certbot certonly --nginx -d example.com -d www.example.com -d api.example.com
```

### Scenario 4: Migration from Existing Server

```bash
# On old server - Create backup
sudo cert-manager
# Select: 7) Backup Certificates

# Copy backup to new server
scp /var/backups/cert-manager/cert-backup-*.tar.gz newserver:/tmp/

# On new server - Restore
sudo cert-manager
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

2. Wait for DNS to propagate (can take up to 48 hours)

3. Verify your domain registrar's DNS settings

4. Use online tools: https://www.whatsmydns.net/

### HTTP-01 Challenge Failed

**Problem:** "Challenge validation failed"

**Common causes and fixes:**

1. **Port 80 blocked:**
   ```bash
   # Check firewall
   sudo ufw status

   # Allow port 80
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   ```

2. **Web server not running:**
   ```bash
   # Check nginx status
   sudo systemctl status nginx

   # Start nginx
   sudo systemctl start nginx
   ```

3. **Incorrect web server configuration:**
   ```bash
   # Test nginx config
   sudo nginx -t

   # View error logs
   sudo tail -f /var/log/nginx/error.log
   ```

4. **Domain not pointing to server:**
   ```bash
   # Verify DNS
   curl -v http://example.com/.well-known/acme-challenge/test
   ```

### DNS-01 Challenge Failed

**Problem:** "DNS TXT record not found"

**Solutions:**

1. **Verify TXT record:**
   ```bash
   dig TXT _acme-challenge.example.com
   ```

2. **Wait for DNS propagation:**
   - Can take 5-10 minutes
   - Check multiple DNS servers

3. **Check DNS provider:**
   - Some providers have propagation delays
   - CloudFlare is typically fastest (1-2 minutes)

### Certificate Not Renewing

**Problem:** Auto-renewal not working

**Debug steps:**

1. **Check timer status:**
   ```bash
   sudo systemctl status cert-renewal.timer
   sudo systemctl list-timers | grep cert-renewal
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
   sudo cert-manager
   # Select: 6) Setup Auto-Renewal
   ```

### Web Server Configuration Issues

**Problem:** Nginx/Apache not loading SSL config

**Solutions:**

1. **Test configuration:**
   ```bash
   # Nginx
   sudo nginx -t

   # Apache
   sudo apache2ctl configtest
   ```

2. **Check if site is enabled:**
   ```bash
   # Nginx
   ls -la /etc/nginx/sites-enabled/

   # Apache
   a2ensite example.com
   ```

3. **Reload web server:**
   ```bash
   sudo systemctl reload nginx
   # or
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
- **Security headers:**
  - HSTS (HTTP Strict Transport Security)
  - X-Frame-Options
  - X-Content-Type-Options
  - X-XSS-Protection
  - Referrer-Policy
- **Optimized SSL session caching**
- **Backend proxy configuration**
- **Static file serving with caching**

**Configuration location:** `/etc/nginx/sites-available/yourdomain.com`

### Apache Configuration (Generated by Script)

Includes:

- **SSL/TLS encryption**
- **HTTP to HTTPS redirect**
- **Security headers**
- **Proxy configuration**
- **Logging**

**Configuration location:** `/etc/apache2/sites-available/yourdomain.com.conf`

---

## 🛡️ Security Best Practices

### 1. Regular Updates

```bash
# Update certbot
sudo apt update && sudo apt upgrade certbot

# Keep the script updated
wget --no-check-certificate https://raw.githubusercontent.com/pgwiz/scripts/refs/heads/master/cert-manager.sh -O /usr/local/bin/cert-manager
```

### 2. Monitor Certificate Expiry

```bash
# Check expiry dates regularly
sudo cert-manager
# Select: 9) Check Certificate Expiry
```

### 3. Backup Certificates

```bash
# Monthly backups recommended
sudo cert-manager
# Select: 7) Backup Certificates

# Store backups off-server
scp /var/backups/cert-manager/*.tar.gz backup-server:/backups/
```

### 4. Test SSL Configuration

```bash
# Test your SSL setup
sudo cert-manager
# Select: 10) Test SSL Configuration

# Or use online tools:
# https://www.ssllabs.com/ssltest/
```

### 5. Limit Certificate Requests

- Let's Encrypt has rate limits (50 certificates per domain per week)
- Use `--staging` flag for testing
- The script automatically handles this

### 6. Secure Private Keys

```bash
# Check private key permissions
ls -la /etc/letsencrypt/live/*/privkey.pem

# Should be: -rw-r----- root root
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
├── archive/                  # Certificate history
└── renewal/                  # Renewal configuration
```

### Script Configuration

```
/etc/cert-manager/           # Configuration files
/var/log/cert-manager/       # Logs
/var/backups/cert-manager/   # Backups
```

### Web Server Configurations

```
# Nginx
/etc/nginx/sites-available/  # Available sites
/etc/nginx/sites-enabled/    # Enabled sites

# Apache
/etc/apache2/sites-available/
/etc/apache2/sites-enabled/
```

---

## 🐧 Django Deployment Scripts

### Ubuntu - Django with Gunicorn

```bash
wget --no-check-certificate https://raw.githubusercontent.com/pgwiz/scripts/refs/heads/master/django_scripts/djang_one.sh -O django.sh && bash django.sh
```

**Features:**
- Automated Django setup
- Gunicorn configuration
- Systemd service creation
- Nginx configuration
- Static file serving

### Debian - Django with Gunicorn

```bash
wget --no-check-certificate https://raw.githubusercontent.com/pgwiz/scripts/refs/heads/master/django_scripts/django_one_debian.sh -O django.sh && bash django.sh
```

### Manual SSL Installation (Legacy)

**Note:** Use the Advanced Certificate Manager instead for better features.

```bash
wget --no-check-certificate https://raw.githubusercontent.com/pgwiz/scripts/refs/heads/master/django_scripts/domain_ssl.sh -O ssl_cert.sh && bash ssl_cert.sh
```

### Git Pull Script

```bash
wget --no-check-certificate https://raw.githubusercontent.com/pgwiz/scripts/refs/heads/master/django_scripts/git_pull.sh -O git_pull.sh && bash git_pull.sh
```

---

## 🔄 Complete Deployment Workflow

### Full Stack Deployment (Django + SSL + Auto-Renewal)

```bash
# Step 1: Deploy Django application (Ubuntu)
wget --no-check-certificate https://raw.githubusercontent.com/pgwiz/scripts/refs/heads/master/django_scripts/djang_one.sh -O django.sh && bash django.sh

# Step 2: Install and configure SSL
wget --no-check-certificate https://raw.githubusercontent.com/pgwiz/scripts/refs/heads/master/cert-manager.sh -O cert-manager.sh && sudo bash cert-manager.sh

# In the Certificate Manager:
# 1) Issue New Certificate
#    - Enter your domain
#    - Select HTTP-01 challenge
#    - Configure web server: Yes
#
# 6) Setup Auto-Renewal
#    - Automatic daily renewal checks
#
# 0) Exit

# Step 3: Verify deployment
curl -I https://yourdomain.com

# Step 4: Test SSL
# Visit: https://www.ssllabs.com/ssltest/analyze.html?d=yourdomain.com
```

---

## 🆘 Support & Additional Resources

### Logs

```bash
# Certificate Manager logs
sudo tail -f /var/log/cert-manager/cert-manager.log

# Let's Encrypt logs
sudo tail -f /var/log/letsencrypt/letsencrypt.log

# Nginx logs
sudo tail -f /var/log/nginx/error.log
sudo tail -f /var/log/nginx/access.log

# Apache logs
sudo tail -f /var/log/apache2/error.log
```

### Useful Commands

```bash
# List all certificates
sudo certbot certificates

# Test renewal
sudo certbot renew --dry-run

# Revoke certificate
sudo certbot revoke --cert-name example.com

# Delete certificate
sudo certbot delete --cert-name example.com

# Check web server status
sudo systemctl status nginx
sudo systemctl status apache2

# Reload web server
sudo systemctl reload nginx
sudo systemctl reload apache2
```

### Let's Encrypt Documentation

- Official Docs: https://letsencrypt.org/docs/
- Rate Limits: https://letsencrypt.org/docs/rate-limits/
- Challenge Types: https://letsencrypt.org/docs/challenge-types/
- Staging Environment: https://letsencrypt.org/docs/staging-environment/

### SSL Testing Tools

- SSL Labs: https://www.ssllabs.com/ssltest/
- SSL Checker: https://www.sslshopper.com/ssl-checker.html
- Certificate Decoder: https://www.sslshopper.com/certificate-decoder.html

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

MIT License - Free to use and modify

## 🤝 Contributing

Found a bug or want to contribute? Issues and pull requests are welcome!

Repository: https://github.com/pgwiz/scripts

---

## ⚡ Quick Reference

### Most Common Commands

```bash
# Install Certificate Manager
wget --no-check-certificate https://raw.githubusercontent.com/pgwiz/scripts/refs/heads/master/cert-manager.sh -O cert-manager.sh && sudo bash cert-manager.sh

# Run Certificate Manager
sudo cert-manager

# Test renewal
sudo certbot renew --dry-run

# List certificates
sudo certbot certificates

# Check nginx
sudo nginx -t && sudo systemctl reload nginx
```

---

**Need Help?** Check the troubleshooting section or view the logs for detailed error messages.
