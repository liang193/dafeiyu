#!/usr/bin/env bash
set -euo pipefail
ROOT=/var/lib/feiyu/qq-runtime
IMAGE=ghcr.io/napneko/nodenapcat@sha256:9f35df29e9f0a92f737143e123b9159b998c314a573139b5ac0e6bd4ab5af574
install -d -o feiyu -g feiyu -m 700 "$ROOT"
if [[ ! -f "$ROOT/config/webui.json" ]]; then
  runuser -u feiyu -- python3 /opt/feiyu/source/scripts/init-qq-config.py --directory "$ROOT/config"
fi
install -d -o feiyu -g feiyu -m 700 "$ROOT/plugins" "$ROOT/logs" "$ROOT/cache"
if ! docker container inspect feiyu-qq >/dev/null 2>&1; then
  docker volume create feiyu-qq-data >/dev/null
  docker run --rm --network none --entrypoint /bin/sh \
    --mount type=volume,source=feiyu-qq-data,target=/app/.config/QQ \
    "$IMAGE" -c "chown $(id -u feiyu):$(id -g feiyu) /app/.config/QQ"
  docker create --name feiyu-qq --hostname feiyu-qq-runtime --init \
    --restart=no --memory=2g --cpus=2 --pids-limit=512 \
    --security-opt=no-new-privileges:true --cap-drop=ALL \
    --user "$(id -u feiyu):$(id -g feiyu)" \
    -e HOME=/app -e XDG_CONFIG_HOME=/app/.config -e NAPCAT_DISABLE_BYPASS=1 \
    -p 127.0.0.1:6099:6099 -p 127.0.0.1:3001:3001 \
    --mount "type=bind,source=$ROOT/config,target=/app/napcat/config" \
    --mount "type=bind,source=$ROOT/plugins,target=/app/napcat/plugins" \
    --mount "type=bind,source=$ROOT/logs,target=/app/napcat/logs" \
    --mount "type=bind,source=$ROOT/cache,target=/app/napcat/cache" \
    --mount type=volume,source=feiyu-qq-data,target=/app/.config/QQ \
    --log-driver=local --log-opt max-size=1m --log-opt max-file=2 \
    --entrypoint /usr/local/bin/node "$IMAGE" /app/load.cjs >/dev/null
fi
docker start feiyu-qq >/dev/null
echo 'QQ bridge started on loopback ports 6099 and 3001.'
