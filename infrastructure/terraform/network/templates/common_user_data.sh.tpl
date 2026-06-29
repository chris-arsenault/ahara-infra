#!/bin/bash
set -euxo pipefail

dnf -y upgrade --refresh

cat >/usr/local/bin/apply-system-hardening.sh <<'EOF'
${HARDENING_SCRIPT}
EOF

chmod 700 /usr/local/bin/apply-system-hardening.sh
/usr/local/bin/apply-system-hardening.sh

systemctl disable --now amazon-cloudwatch-agent.service || true

rpm --import https://rpm.grafana.com/gpg.key
cat >/etc/yum.repos.d/grafana.repo <<'EOF'
[grafana]
name=grafana
baseurl=https://rpm.grafana.com
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://rpm.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF

dnf -y install alloy

getent group adm >/dev/null && usermod -aG adm alloy || true
getent group systemd-journal >/dev/null && usermod -aG systemd-journal alloy || true

mkdir -p /etc/alloy
mkdir -p /var/lib/alloy

cat >/etc/alloy/config.alloy <<'EOF'
${ALLOY_CONFIG}
EOF

cat >/etc/sysconfig/alloy <<'EOF'
CONFIG_FILE=/etc/alloy/config.alloy
CUSTOM_ARGS="--server.http.listen-addr=127.0.0.1:12345 --storage.path=/var/lib/alloy"
EOF

${EXTRA_SNIPPET}

systemctl daemon-reload
systemctl enable --now alloy
