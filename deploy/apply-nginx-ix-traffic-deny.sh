#!/bin/bash
# default.conf の /ix-traffic に scripts・systemd・deploy・ドットファイル拒否を追加する。
# 参照: deploy/nginx-ix-traffic-locations.snippet
# 使い方: sudo bash /var/www/ix-traffic/deploy/apply-nginx-ix-traffic-deny.sh

set -euo pipefail

CONF=/etc/nginx/conf.d/default.conf

python3 << 'PY'
import re
from pathlib import Path

path = Path("/etc/nginx/conf.d/default.conf")
text = path.read_text()

deny_dirs = r"location ~ \^/ix-traffic/\(scripts\|systemd\|deploy\)/"
deny_dirs_old = r"location ~ \^/ix-traffic/\(scripts\|systemd\)/"
deny_dot = r"location ~ \^/ix-traffic/\\\.\s+\{"

if re.search(deny_dirs, text):
    print("Deny locations already up to date (includes deploy).")
elif re.search(deny_dirs_old, text):
    text, n = re.subn(
        r"\(scripts\|systemd\)/",
        "(scripts|systemd|deploy)/",
        text,
        count=1,
    )
    if n != 1:
        raise SystemExit("failed to add deploy to existing deny location")
    path.write_text(text)
    print("Updated deny location to include deploy.")
elif re.search(deny_dot, text) or re.search(r"# claude code ix traffic\n\s+location /ix-traffic/", text):
    marker = "    # claude code ix traffic\n    location /ix-traffic/ {"
    if marker not in text:
        raise SystemExit("default.conf: /ix-traffic/ catch-all not found")
    insert = """    location ~ ^/ix-traffic/(scripts|systemd|deploy)/ {
        deny all;
        return 404;
    }

    location ~ ^/ix-traffic/\\. {
        deny all;
        return 404;
    }

    # claude code ix traffic
    location /ix-traffic/ {"""
    path.write_text(text.replace(marker, insert, 1))
    print("Inserted deny locations before /ix-traffic/ catch-all.")
else:
    raise SystemExit("default.conf: no matching /ix-traffic block to patch")
PY

nginx -t
systemctl reload nginx
echo "nginx reloaded."