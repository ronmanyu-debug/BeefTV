#!/bin/sh
# BeefTV Zeabur entrypoint: Basic Auth setup + run backend & nginx.
#
# BEEFTV_AUTH must be set to "username:password" (no colon inside the password).
# Roman sets it himself in the Zeabur dashboard -> Variables; the plaintext is
# hashed here at container start and never written to the repo or an image layer.
set -eu

cd /app
mkdir -p /data

if [ -z "${BEEFTV_AUTH:-}" ]; then
  echo "ERROR: BEEFTV_AUTH is not set. Set it to \"username:password\" in the Zeabur dashboard -> Variables." >&2
  exit 1
fi
auth_user="${BEEFTV_AUTH%%:*}"
auth_pass="${BEEFTV_AUTH#*:}"
if [ -z "$auth_user" ] || [ -z "$auth_pass" ] || [ "$auth_user" = "$BEEFTV_AUTH" ]; then
  echo "ERROR: BEEFTV_AUTH must look like \"username:password\" (password must not contain ':')." >&2
  exit 1
fi
auth_hash="$(openssl passwd -apr1 "$auth_pass")"
printf '%s:%s\n' "$auth_user" "$auth_hash" > /etc/nginx/.htpasswd
chmod 600 /etc/nginx/.htpasswd
unset auth_pass BEEFTV_AUTH

# Backend first (sqlite auto-migrates into /data on boot).
/usr/local/bin/infinite-canvas-backend &
backend_pid=$!

# nginx in background so we can supervise both processes.
nginx -g 'daemon off;' &
nginx_pid=$!

_term() {
  kill -TERM "$backend_pid" 2>/dev/null || true
  kill -TERM "$nginx_pid" 2>/dev/null || true
}
trap _term TERM INT

# If either process dies, shut the other down and exit non-zero
# so Zeabur restarts the container.
while true; do
  if ! kill -0 "$backend_pid" 2>/dev/null; then
    echo "backend exited unexpectedly" >&2
    _term
    exit 1
  fi
  if ! kill -0 "$nginx_pid" 2>/dev/null; then
    echo "nginx exited unexpectedly" >&2
    _term
    exit 1
  fi
  sleep 5
done
