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
  echo "failed to detect outbound connectivity after $MAX_ATTEMPTS attempts; continuing but package installs may fail" >&2
fi

for attempt in $(seq 1 10); do
  if dnf -y install nginx; then
    break
  fi
  echo "dnf install nginx failed (attempt $attempt/10); retrying in 15s" >&2
  sleep 15
done

rm -f /etc/nginx/conf.d/default.conf

cat >/etc/nginx/conf.d/reverse-proxy.conf <<'EOF'
map $http_upgrade $proxy_connection_upgrade {
  default upgrade;
  ''      close;
}

map $http_x_forwarded_proto $proxy_forwarded_proto {
  default $http_x_forwarded_proto;
  ''      $scheme;
}

%{ for host, route in ROUTES ~}
server {
  listen 80;
  server_name ${host};

%{ if try(route.max_body_size, "") != "" ~}
  client_max_body_size ${route.max_body_size};
%{ endif ~}

  location / {
    proxy_pass http://${route.address}:${route.port};
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $proxy_forwarded_proto;
%{ if try(route.websocket, false) ~}
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $proxy_connection_upgrade;
%{ else ~}
    proxy_set_header Connection "";
%{ endif ~}
%{ if try(route.buffering, "") == "off" ~}
    # Streaming/SSE-friendly: forward events immediately and hold the
    # long-lived upstream connection open.
    proxy_buffering off;
    proxy_cache off;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
%{ endif ~}
  }

  access_log /var/log/nginx/${host}_access.log;
  error_log  /var/log/nginx/${host}_error.log warn;
}
%{ endfor }
EOF

systemctl enable --now nginx

# /var/log/nginx ships as root:root drwx--x--x, so only root can list it —
# Vector (root) can read the logs, but Alloy (runs as the unprivileged
# 'alloy' user, already a member of 'adm' for exactly this purpose per
# install_alloy()) cannot glob-discover files there, so nginx-access/error
# never reach Loki even though CloudWatch has them. Group-read the directory
# for 'adm'; the individual log files are already world-readable (644).
chgrp adm /var/log/nginx
chmod 750 /var/log/nginx
