#!/usr/bin/env bash
# install-clip-client.sh — добавляет clip-команды в ~/.bashrc
# usage:  ./install-clip-client.sh
#         CLIP_HOST=cpbrd.duckdns.org:8443 CLIP_TOKEN=secret ./install-clip-client.sh

set -eu

DEFAULT_HOST="cpbrd.duckdns.org:8443"

# ---- параметры ----
HOST="${CLIP_HOST:-}"
TOKEN="${CLIP_TOKEN:-}"

if [ -z "$HOST" ]; then
  read -rp "CLIP_HOST [$DEFAULT_HOST]: " HOST
  HOST="${HOST:-$DEFAULT_HOST}"
fi

if [ -z "$TOKEN" ]; then
  read -rsp "CLIP_TOKEN: " TOKEN; echo
fi

[ -z "$TOKEN" ] && { echo "error: пустой токен" >&2; exit 1; }

RC="${BASHRC:-$HOME/.bashrc}"
MARK_BEGIN="# >>> clip client >>>"
MARK_END="# <<< clip client <<<"

# ---- проверка соединения ----
echo "проверяю https://$HOST/raw ..."
code=$(curl -sS -o /dev/null -w '%{http_code}' \
            -H "X-Token: $TOKEN" "https://$HOST/raw" || echo "000")
case "$code" in
  200) echo "✓ сервер отвечает, токен подходит" ;;
  403) echo "✗ 403 — токен не подходит"; exit 1 ;;
  000) echo "✗ не могу подключиться к $HOST"; exit 1 ;;
  *)   echo "! сервер ответил $code (продолжаю)" ;;
esac

# ---- удалить старый блок если есть ----
if grep -qF "$MARK_BEGIN" "$RC" 2>/dev/null; then
  echo "удаляю предыдущий блок clip из $RC"
  sed -i.bak "/$MARK_BEGIN/,/$MARK_END/d" "$RC"
fi

# ---- добавить новый блок ----
cat >> "$RC" <<EOF
$MARK_BEGIN
export CLIP_HOST="$HOST"
export CLIP_TOKEN="$TOKEN"

_clip_help='clip — буфер обмена через VPS (https://'\$CLIP_HOST')

Текст:
  clip                       вывести текст из буфера
  clipw <текст>              записать строку в буфер
  echo foo | clipw           записать из stdin
  clipw < file.txt           записать из файла

Файлы:
  clipls                     список файлов с датой и размером
  clipget <name> [dir]       скачать файл (dir по умолчанию: текущая)
  clipput <file>             залить файл в буфер

Прочее:
  cliphelp, clip -h          показать эту справку
  Веб-интерфейс:             https://'\$CLIP_HOST

cliphelp() { echo "\$_clip_help"; }

clip() {
  case "\$1" in -h|--help) echo "\$_clip_help"; return ;; esac
  curl -fsS -H "X-Token: \$CLIP_TOKEN" "https://\$CLIP_HOST/raw"; echo
}

clipw() {
  case "\$1" in -h|--help) echo "\$_clip_help"; return ;; esac
  if [ \$# -gt 0 ]; then
    printf '%s' "\$*" | curl -fsS -X PUT --data-binary @- \\
      -H "X-Token: \$CLIP_TOKEN" "https://\$CLIP_HOST/raw"
  else
    curl -fsS -X PUT --data-binary @- \\
      -H "X-Token: \$CLIP_TOKEN" "https://\$CLIP_HOST/raw"
  fi
}

clipls() {
  case "\$1" in -h|--help) echo "\$_clip_help"; return ;; esac
  local resp
  resp=\$(curl -fsS -H "X-Token: \$CLIP_TOKEN" "https://\$CLIP_HOST/files") || return 1
  CLIP_DATA="\$resp" python3 <<'PY'
import json, os, datetime as dt
data = json.loads(os.environ.get("CLIP_DATA") or "[]")
if not data:
    print("(empty)"); raise SystemExit
for f in data:
    t = dt.datetime.fromtimestamp(f["mtime"]).strftime("%m-%d %H:%M")
    print(f'{f["size"]:>10}  {t}  {f["name"]}')
PY
}

clipget() {
  case "\$1" in -h|--help|"") echo "\$_clip_help"; return ;; esac
  local name="\$1" dest="\${2:-.}"
  mkdir -p "\$dest"
  curl -fsS -H "X-Token: \$CLIP_TOKEN" -o "\$dest/\$name" \\
    "https://\$CLIP_HOST/file/\$name" && echo "→ \$dest/\$name"
}

clipput() {
  case "\$1" in -h|--help|"") echo "\$_clip_help"; return ;; esac
  curl -fsS -H "X-Token: \$CLIP_TOKEN" -F "file=@\$1" "https://\$CLIP_HOST/upload"
  echo
}
$MARK_END
EOF

echo
echo "✓ clip установлен в $RC"
echo
echo "примени изменения:"
echo "  source $RC"
echo
echo "проверь:"
echo "  cliphelp"
echo "  clipls"
