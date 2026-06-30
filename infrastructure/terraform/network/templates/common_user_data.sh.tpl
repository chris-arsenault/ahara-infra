#!/bin/bash
set -euxo pipefail

run_optional() {
  local name="$1"
  shift
  set +e
  (set -euo pipefail; "$@")
  local status=$?
  set -e

  if [ "$status" -ne 0 ]; then
    echo "optional setup failed: $name (exit $status)" >&2
  fi
}

apply_hardening() {
  cat >/usr/local/bin/apply-system-hardening.sh <<'EOF'
${HARDENING_SCRIPT}
EOF

  chmod 700 /usr/local/bin/apply-system-hardening.sh
  /usr/local/bin/apply-system-hardening.sh
}

ensure_bootstrap_swap() {
  if swapon --show=NAME --noheadings | grep -qx '/swapfile'; then
    return 0
  fi

  if [ ! -f /swapfile ]; then
    fallocate -l 1G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=1024
    chmod 600 /swapfile
    mkswap /swapfile
  fi

  swapon /swapfile

  if ! grep -q '^/swapfile ' /etc/fstab; then
    echo '/swapfile none swap sw 0 0' >>/etc/fstab
  fi
}

install_alloy() {
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

  systemctl daemon-reload
  systemctl enable --now alloy
}

install_vector_cloudwatch() {
  export HOME="$${HOME:-/root}"
  curl --proto '=https' --tlsv1.2 -sSfL https://sh.vector.dev | bash -s -- -y

  TOKEN="$(curl -sS -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600')"
  INSTANCE_ID="$(curl -sS -H "X-aws-ec2-metadata-token: $${TOKEN}" http://169.254.169.254/latest/meta-data/instance-id)"
  AWS_REGION="$(curl -sS -H "X-aws-ec2-metadata-token: $${TOKEN}" http://169.254.169.254/latest/meta-data/placement/region)"

  mkdir -p /etc/vector
  mkdir -p /var/lib/vector

  cat >/etc/vector/environment <<EOF
INSTANCE_ID=$${INSTANCE_ID}
AWS_REGION=$${AWS_REGION}
EOF

  cat >/etc/vector/vector.toml <<'EOF'
${VECTOR_CONFIG}
EOF

  cat >/etc/systemd/system/vector.service <<'EOF'
${VECTOR_SERVICE_UNIT}
EOF

  mkdir -p /etc/systemd/system/vector.service.d

  cat >/etc/systemd/system/vector.service.d/override.conf <<'EOF'
${VECTOR_SERVICE_OVERRIDE}
EOF

  systemctl daemon-reload
  systemctl enable --now vector
}

# Critical network/application setup must run before package-heavy hardening or
# telemetry setup. NAT and WireGuard are single-instance network dependencies.
${EXTRA_SNIPPET}

run_optional "bootstrap swap" ensure_bootstrap_swap
run_optional "dnf security refresh" dnf -y upgrade --refresh
run_optional "system hardening" apply_hardening
run_optional "alloy telemetry" install_alloy
run_optional "cloudwatch log forwarding" install_vector_cloudwatch
