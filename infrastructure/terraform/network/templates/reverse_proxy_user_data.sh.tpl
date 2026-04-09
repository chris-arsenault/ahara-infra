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
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Connection "";
  }

  access_log /var/log/nginx/${host}_access.log;
  error_log  /var/log/nginx/${host}_error.log warn;
}
%{ endfor }
EOF

systemctl enable --now nginx
