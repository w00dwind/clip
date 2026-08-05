#!/usr/bin/env bash
# install-clip-client.sh — добавляет clip-команды в ~/.bashrc или ~/.zshrc
# usage:
#   ./install-clip-client.sh                       # автоопределение shell
#   ./install-clip-client.sh --shell bash          # явно bash
#   ./install-clip-client.sh --shell zsh           # явно zsh
#   ./install-clip-client.sh --rc ~/.config/myrc   # произвольный файл
#   CLIP_HOST=... CLIP_TOKEN=... ./install-clip-client.sh
#   ./install-clip-client.sh --uninstall

set -eu

DEFAULT_HOST="cpbrd.duckdns.org:8443"
# ponytail: сервер с self-signed сертификатом (доступ по IP, без домена) —
# curl без -k откажется. Если у тебя валидный сертификат: CLIP_TLS="" ./client.sh
CLIP_TLS="${CLIP_TLS--k}"
SHELL_HINT=""
RC=""
UNINSTALL="no"

# ---- разбор аргументов ----
while [ $# -gt 0 ]; do
  case "$1" in
    --shell) SHELL_HINT="$2"; shift 2 ;;
    --rc)    RC="$2"; shift 2 ;;
    --uninstall) UNINSTALL="yes"; shift ;;
    -h|--help)
      sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "неизвестный аргумент: $1" >&2; exit 2 ;;
  esac
done

# ---- определить shell ----
detect_shell() {
  # 1. явный hint
  if [ -n "$SHELL_HINT" ]; then echo "$SHELL_HINT"; return; fi
  # 2. родительский процесс (но скрипт запускается через bash, поэтому ненадёжно)
  # 3. $SHELL — что у пользователя в /etc/passwd
  case "${SHELL:-}" in
    */zsh)  echo "zsh";  return ;;
    */bash) echo "bash"; return ;;
  esac
  # 4. наличие rc-файлов
  [ -f "$HOME/.zshrc" ]  && { echo "zsh";  return; }
  [ -f "$HOME/.bashrc" ] && { echo "bash"; return; }
  # 5. дефолт
  echo "bash"
}

SH="$(detect_shell)"
case "$SH" in
  bash) RC_DEFAULT="$HOME/.bashrc" ;;
  zsh)  RC_DEFAULT="$HOME/.zshrc"  ;;
  *) echo "неподдерживаемый shell: $SH (используй --shell bash|zsh)" >&2; exit 2 ;;
esac

RC="${RC:-$RC_DEFAULT}"
MARK_BEGIN="# >>> clip client >>>"
MARK_END="# <<< clip client <<<"

# ---- удалить старый блок (для install и uninstall) ----
remove_old_block() {
  if [ -f "$RC" ] && grep -qF "$MARK_BEGIN" "$RC"; then
    echo "удаляю предыдущий блок clip из $RC (бэкап → ${RC}.bak)"
    sed -i.bak "/$MARK_BEGIN/,/$MARK_END/d" "$RC"
    return 0
  fi
  return 1
}

if [ "$UNINSTALL" = "yes" ]; then
  echo "shell: $SH | файл: $RC"
  if remove_old_block; then
    echo "✓ блок clip удалён. примени: source $RC"
  else
    echo "блок clip не найден в $RC"
  fi
  exit 0
fi

# ---- параметры ----
HOST="${CLIP_HOST:-}"
TOKEN="${CLIP_TOKEN:-}"

if [ -z "$HOST" ]; then
  printf "CLIP_HOST [%s]: " "$DEFAULT_HOST"
  read -r HOST
  HOST="${HOST:-$DEFAULT_HOST}"
fi

if [ -z "$TOKEN" ]; then
  printf "CLIP_TOKEN: "
  stty -echo 2>/dev/null || true
  read -r TOKEN
  stty echo 2>/dev/null || true
  echo
fi

[ -z "$TOKEN" ] && { echo "error: пустой токен" >&2; exit 1; }

# ---- проверка соединения ----
echo "shell: $SH | файл: $RC"
echo "проверяю https://$HOST/raw ..."
code=$(curl $CLIP_TLS -sS -o /dev/null -w '%{http_code}' \
            -H "X-Token: $TOKEN" "https://$HOST/raw" || echo "000")
case "$code" in
  200) echo "✓ сервер отвечает, токен подходит" ;;
  403) echo "✗ 403 — токен не подходит"; exit 1 ;;
  000) echo "✗ не могу подключиться к $HOST"; exit 1 ;;
  *)   echo "! сервер ответил $code (продолжаю)" ;;
esac

remove_old_block || true

# ---- записать блок ----
# zsh поддерживает тот же синтаксис функций, что и bash, плюс local/case/printf
# единственное отличие — в zsh `$1` внутри функции без аргументов даёт ошибку
# при `set -u`, но у нас set -u не используется в .bashrc/.zshrc, так что ок.

cat >> "$RC" <<EOF
$MARK_BEGIN
export CLIP_HOST="$HOST"
export CLIP_TOKEN="$TOKEN"
export CLIP_TLS="$CLIP_TLS"

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
  case "\${1:-}" in -h|--help) echo "\$_clip_help"; return ;; esac
  curl \$CLIP_TLS -fsS -H "X-Token: \$CLIP_TOKEN" "https://\$CLIP_HOST/raw"; echo
}

clipw() {
  case "\${1:-}" in -h|--help) echo "\$_clip_help"; return ;; esac
  if [ \$# -gt 0 ]; then
    printf '%s' "\$*" | curl \$CLIP_TLS -fsS -X PUT --data-binary @- \\
      -H "X-Token: \$CLIP_TOKEN" "https://\$CLIP_HOST/raw"
  else
    curl \$CLIP_TLS -fsS -X PUT --data-binary @- \\
      -H "X-Token: \$CLIP_TOKEN" "https://\$CLIP_HOST/raw"
  fi
}

clipls() {
  case "\${1:-}" in -h|--help) echo "\$_clip_help"; return ;; esac
  local resp
  resp=\$(curl \$CLIP_TLS -fsS -H "X-Token: \$CLIP_TOKEN" "https://\$CLIP_HOST/files") || return 1
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
  case "\${1:-}" in -h|--help|"") echo "\$_clip_help"; return ;; esac
  local name="\$1" dest="\${2:-.}"
  mkdir -p "\$dest"
  curl \$CLIP_TLS -fsS -H "X-Token: \$CLIP_TOKEN" -o "\$dest/\$name" \\
    "https://\$CLIP_HOST/file/\$name" && echo "→ \$dest/\$name"
}

clipput() {
  case "\${1:-}" in -h|--help|"") echo "\$_clip_help"; return ;; esac
  curl \$CLIP_TLS -fsS -H "X-Token: \$CLIP_TOKEN" -F "file=@\$1" "https://\$CLIP_HOST/upload"
  echo
}
$MARK_END
EOF

echo
echo "✓ clip установлен в $RC"
echo
echo "примени:"
echo "  source $RC"
echo
echo "проверь:"
echo "  cliphelp"
echo "  clipls"
