# Home peer config: put this on your home router/box that dials OUT to AWS.
# Replace <HOME_PRIVATE_KEY> with the private key you generate on your home box.
%{ if SERVER_PUBKEY == "PENDING" }
# NOTE: The WireGuard server has not yet reported its public key. After the instance finishes bootstrapping, run:
#   aws ssm get-parameter --name "${SSM_PARAM}"
# and update the PublicKey field below with the returned value, then re-run `terraform output home_peer_config`.
%{ endif }

[Interface]
PrivateKey = <HOME_PRIVATE_KEY>
# Use one address inside the WG CIDR; .2 is common if server uses .1
Address = ${WG_ADDRESS}
DNS = ${WG_DNS}

[Peer]
PublicKey = ${SERVER_PUBKEY}
AllowedIPs = ${WG_CIDR},${AWS_PRIVATE_CIDR}
Endpoint = ${ENDPOINT}
PersistentKeepalive = 25
