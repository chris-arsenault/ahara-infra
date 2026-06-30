CONNECTIVITY_TARGET="https://cdn.amazonlinux.com"
CONNECTIVITY_READY=0
MAX_ATTEMPTS=60

for attempt in $(seq 1 $MAX_ATTEMPTS); do
  if curl --proto '=https' --tlsv1.2 --silent --location --head --connect-timeout 5 "$CONNECTIVITY_TARGET" >/dev/null; then
    CONNECTIVITY_READY=1
    echo "outbound connectivity available after $attempt attempt(s)" >&2
    break
  fi
  echo "waiting for outbound connectivity (attempt $attempt/$MAX_ATTEMPTS)" >&2
  sleep 10
done

if [ "$CONNECTIVITY_READY" -ne 1 ]; then
  echo "failed to detect outbound connectivity after $MAX_ATTEMPTS attempts; package installs may fail" >&2
fi

IPTABLES_INSTALLED=0
for attempt in $(seq 1 10); do
  if dnf -y install iptables-services; then
    IPTABLES_INSTALLED=1
    break
  fi
  echo "dnf install iptables-services failed (attempt $attempt/10); retrying in 15s" >&2
  sleep 15
done

if [ "$IPTABLES_INSTALLED" -ne 1 ]; then
  echo "failed to install iptables-services; NAT cannot be configured" >&2
  exit 1
fi

cat >/etc/sysctl.d/99-nat.conf <<'EOF'
net.ipv4.ip_forward = 1
EOF

sysctl --system

PRIMARY_IF="$(ip -o route get 1.1.1.1 | awk 'NR==1 {print $5}')"

if [ -z "$PRIMARY_IF" ]; then
  echo "failed to detect primary network interface for NAT instance" >&2
  exit 1
fi

cat >/etc/sysconfig/iptables <<EOF
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A FORWARD -m conntrack --ctstate INVALID -m limit --limit 5/min --limit-burst 10 -j LOG --log-prefix "NAT_INVALID " --log-level 4
-A FORWARD -m conntrack --ctstate INVALID -j DROP
-A FORWARD -i $${PRIMARY_IF} -o $${PRIMARY_IF} -m state --state RELATED,ESTABLISHED -j ACCEPT
-A FORWARD -s ${PRIVATE_SUBNET_CIDR} -o $${PRIMARY_IF} -j ACCEPT
-A FORWARD -m limit --limit 5/min --limit-burst 10 -j LOG --log-prefix "NAT_UNMATCHED " --log-level 4
COMMIT
*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -o $${PRIMARY_IF} -j MASQUERADE
COMMIT
EOF

systemctl enable --now iptables
