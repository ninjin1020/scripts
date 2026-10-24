#!/usr/bin/env bash
# Install anytls (sing-box) on Debian/Ubuntu and print the share link.
# Usage: bash anytls.sh <domain>
set -euo pipefail

DOMAIN="${1:-}"
[ -n "$DOMAIN" ] || { echo "Usage: bash $0 <domain>" >&2; exit 2; }
[ "$(id -u)" = 0 ] || { echo "Run as root" >&2; exit 1; }
export DEBIAN_FRONTEND=noninteractive

# Install sing-box
if ! command -v sing-box >/dev/null; then
  command -v curl >/dev/null || { apt-get update -qq; apt-get install -y -qq curl >/dev/null; }
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc
  chmod a+r /etc/apt/keyrings/sagernet.asc
  cat > /etc/apt/sources.list.d/sagernet.sources <<'EOF'
Types: deb
URIs: https://deb.sagernet.org/
Suites: *
Components: *
Enabled: yes
Signed-By: /etc/apt/keyrings/sagernet.asc
EOF
  apt-get update -qq
  apt-get install -y -qq sing-box >/dev/null
fi

# Generate password
PASSWORD=$(sing-box generate rand --hex 16)

# Write config
cat > /etc/sing-box/config.json <<EOF
{
  "log": { "level": "warn" },
  "certificate_providers": [
    {
      "type": "acme",
      "tag": "le",
      "domain": ["$DOMAIN"],
      "data_directory": "/var/lib/sing-box/acme",
      "disable_http_challenge": true
    }
  ],
  "inbounds": [
    {
      "type": "anytls",
      "listen": "::",
      "listen_port": 443,
      "users": [{ "name": "user", "password": "$PASSWORD" }],
      "tls": {
        "enabled": true,
        "alpn": ["h2", "http/1.1"],
        "certificate_provider": "le"
      }
    }
  ],
  "route": {
    "rules": [
      { "action": "resolve" },
      { "ip_is_private": true, "action": "reject" }
    ]
  }
}
EOF
sing-box check -C /etc/sing-box

# Start and wait for the certificate
systemctl enable sing-box >/dev/null 2>&1
systemctl restart sing-box
echo "Waiting for the certificate..."
cert() { find /var/lib/sing-box/acme/certificates -name "$DOMAIN.crt" 2>/dev/null | grep -q .; }
for _ in $(seq 45); do cert && break; sleep 2; done
cert || {
  echo "No certificate yet. Check that the A record points to this server, the CDN proxy is off, and TCP 443 is open." >&2
  echo "Logs: journalctl -u sing-box -n 50" >&2
  exit 1
}

# Print share link
echo
echo "Done. Share link:"
echo "anytls://$PASSWORD@$DOMAIN:443/?sni=$DOMAIN#$DOMAIN"
