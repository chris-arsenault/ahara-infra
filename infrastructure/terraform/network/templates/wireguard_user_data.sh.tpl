readonly WG_PORT="${WG_PORT}"
readonly WG_CIDR="${WG_CIDR}"
readonly WG_CIDR_HOST="${WG_CIDR_HOST}"
readonly HOME_LAN="${HOME_LAN_CIDR}"
readonly LAPTOP_PUB="${LAPTOP_PEER_PUBKEY}"
readonly HOME_PUB="${HOME_PEER_PUBKEY}"
readonly PRIVATE_SUBNET="${PRIVATE_SUBNET_CIDR}"
readonly SSM_PUBLIC_KEY_PATH="${SSM_PUBLIC_KEY_PATH}"
readonly AWS_REGION="${AWS_REGION}"
readonly SECRET_ID="${SECRET_ID}"

dnf -y install wireguard-tools iproute iptables-services jq awscli socat

echo 'net.ipv4.ip_forward=1' >/etc/sysctl.d/99-wg.conf
sysctl --system
mkdir -p /etc/wireguard
chmod 700 /etc/wireguard

JSON="$(aws secretsmanager get-secret-value \
  --region "$AWS_REGION" \
  --secret-id "$SECRET_ID" \
  --query SecretString \
  --output text || echo "")"

if [ -z "$JSON" ] || [ "$JSON" = "null" ]; then
  JSON='{"private":"PLACEHOLDER","public":"PLACEHOLDER"}'
fi

PRIV="$(echo "$JSON" | jq -r '.private')"
PUB="$(echo "$JSON" | jq -r '.public')"

umask 077

if [ "$PRIV" = "PLACEHOLDER" ] || [ -z "$PRIV" ] || [ "$PRIV" = "null" ]; then
  wg genkey | tee /etc/wireguard/server_private.key | wg pubkey > /etc/wireguard/server_public.key
  PRIV="$(cat /etc/wireguard/server_private.key)"
  PUB="$(cat /etc/wireguard/server_public.key)"
  aws secretsmanager put-secret-value \
    --region "$AWS_REGION" \
    --secret-id "$SECRET_ID" \
    --secret-string "$(jq -n --arg priv "$PRIV" --arg pub "$PUB" '{private:$priv,public:$pub}')"
else
  printf "%s" "$PRIV" >/etc/wireguard/server_private.key
  printf "%s" "$PUB"  >/etc/wireguard/server_public.key
fi

chmod 600 /etc/wireguard/server_private.key

SERVER_PRIV="$(cat /etc/wireguard/server_private.key)"
SERVER_PUB="$(cat /etc/wireguard/server_public.key)"

aws ssm put-parameter \
  --name "$SSM_PUBLIC_KEY_PATH" \
  --type "String" \
  --value "$SERVER_PUB" \
  --overwrite \
  --region "$AWS_REGION"

PRIMARY_IF="$(ip -o -4 route show to default | awk '{print $5}')"

cat >/etc/wireguard/wg0.conf <<EOF
[Interface]
Address = $WG_CIDR_HOST
ListenPort = $WG_PORT
PrivateKey = $SERVER_PRIV
PostUp   = iptables -t nat -A POSTROUTING -s $WG_CIDR -o $PRIMARY_IF -j MASQUERADE
PostUp   = iptables -A FORWARD -i $PRIMARY_IF -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT
PostUp   = iptables -A FORWARD -i wg0 -o $PRIMARY_IF -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -s $WG_CIDR -o $PRIMARY_IF -j MASQUERADE
PostDown = iptables -D FORWARD -i $PRIMARY_IF -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT
PostDown = iptables -D FORWARD -i wg0 -o $PRIMARY_IF -j ACCEPT
EOF

cat >>/etc/wireguard/wg0.conf <<EOF
[Peer]
PublicKey = $HOME_PUB
AllowedIPs = $HOME_LAN, $WG_CIDR
PersistentKeepalive = 25
EOF

if [ -n "$LAPTOP_PUB" ]; then
  cat >>/etc/wireguard/wg0.conf <<EOF
[Peer]
PublicKey = $LAPTOP_PUB
AllowedIPs = $WG_CIDR, $HOME_LAN, $PRIVATE_SUBNET
PersistentKeepalive = 25
EOF
fi

dnf -y install dnsmasq

cat >/etc/dnsmasq.d/wg-forward.conf <<EOF
interface=wg0
bind-interfaces
listen-address=${WG_SERVER_IP}
server=${VPC_DNS}
no-resolv
cache-size=1000
EOF

mkdir -p /etc/systemd/system/dnsmasq.service.d
cat >/etc/systemd/system/dnsmasq.service.d/after-wg.conf <<EOF
[Unit]
After=wg-quick@wg0.service
Requires=wg-quick@wg0.service
EOF

systemctl daemon-reload
systemctl enable --now wg-quick@wg0
systemctl enable --now dnsmasq

cat >/etc/systemd/system/wg-healthcheck.service <<'EOF'
[Unit]
Description=TCP health check listener for WireGuard NLB
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/socat tcp-l:31000,reuseaddr,fork exec:'/bin/cat'
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now wg-healthcheck.service

wg show
