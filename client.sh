#!/usr/bin/env bash
# install-clip-client.sh — добавляет clip-команды в ~/.bashrc или ~/.zshrc
# usage:
#   ./install-clip-client.sh                       # автоопределение shell
#   ./install-clip-client.sh --shell bash          # явно bash
#   ./install-clip-client.sh --shell zsh           # явно zsh
#   ./install-clip-client.sh --rc ~/.config/myrc   # произвольный файл
#   ./install-clip-client.sh --name aeza           # имя профиля сервера
#   CLIP_HOST=... CLIP_TOKEN=... CLIP_NAME=... ./install-clip-client.sh
#   ./install-clip-client.sh --uninstall
#
# Повторный запуск с другим CLIP_HOST добавляет ещё один профиль;
# переключение между ними — `clip switch <имя>`.

set -eu

DEFAULT_HOST="aeza.frn.dedyn.io:8443"
# ponytail: сервер отдаёт валидный Let's Encrypt сертификат — проверка включена.
# Если ставишь по IP или на self-signed: CLIP_TLS="-k" sh client.sh
CLIP_TLS="${CLIP_TLS-}"
SHELL_HINT=""
RC=""
NAME="${CLIP_NAME:-}"
UNINSTALL="no"
# профили серверов: строки «имя host token [tls]», активный — в файле current
CFG="${CLIP_CONFIG:-$HOME/.config/clip}"

# ---- разбор аргументов ----
while [ $# -gt 0 ]; do
  case "$1" in
    --shell) SHELL_HINT="$2"; shift 2 ;;
    --rc)    RC="$2"; shift 2 ;;
    --name)  NAME="$2"; shift 2 ;;
    --uninstall) UNINSTALL="yes"; shift ;;
    -h|--help)
      sed -n '2,13p' "$0"; exit 0 ;;
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
    echo "профили серверов остались в $CFG (удали вручную, если не нужны)"
  else
    echo "блок clip не найден в $RC"
  fi
  exit 0
fi

# ---- параметры ----
HOST="${CLIP_HOST:-}"
TOKEN="${CLIP_TOKEN:-}"

# при `curl ... | sh` stdin занят самим скриптом — спрашиваем с терминала
if [ -t 0 ]; then TTY=/dev/stdin; else TTY=/dev/tty; fi

if [ -z "$HOST" ]; then
  printf "CLIP_HOST [%s]: " "$DEFAULT_HOST"
  read -r HOST < "$TTY" || true
  HOST="${HOST:-$DEFAULT_HOST}"
fi

if [ -z "$NAME" ]; then
  # дефолт: первая метка домена (aeza.frn.dedyn.io:8443 → aeza), для IP — весь IP
  NAME_DEFAULT="${HOST%%:*}"
  case "$NAME_DEFAULT" in *[!0-9.]*) NAME_DEFAULT="${NAME_DEFAULT%%.*}" ;; esac
  printf "имя профиля [%s]: " "$NAME_DEFAULT"
  read -r NAME < "$TTY" || true
  NAME="${NAME:-$NAME_DEFAULT}"
fi
case "$NAME" in
  ""|*[!A-Za-z0-9._-]*) echo "error: имя профиля — только буквы, цифры, . _ -" >&2; exit 1 ;;
esac

if [ -z "$TOKEN" ]; then
  printf "CLIP_TOKEN: "
  stty -echo < "$TTY" 2>/dev/null || true
  read -r TOKEN < "$TTY" || true
  stty echo < "$TTY" 2>/dev/null || true
  echo
fi

[ -z "$TOKEN" ] && { echo "error: пустой токен" >&2; exit 1; }

# ---- проверка соединения ----
echo "shell: $SH | файл: $RC | профиль: $NAME"
echo "проверяю https://$HOST/raw ..."
code=$(curl $CLIP_TLS -sS -o /dev/null -w '%{http_code}' \
            -H "X-Token: $TOKEN" "https://$HOST/raw" || true)
case "$code" in
  200) echo "✓ сервер отвечает, токен подходит" ;;
  403) echo "✗ 403 — токен не подходит"; exit 1 ;;
  000) echo "✗ не могу подключиться к $HOST"; exit 1 ;;
  *)   echo "! сервер ответил $code (продолжаю)" ;;
esac

# ---- записать профиль и сделать его активным ----
mkdir -p "$CFG"
chmod 700 "$CFG"
touch "$CFG/hosts"
chmod 600 "$CFG/hosts"
awk -v n="$NAME" '$1 != n' "$CFG/hosts" > "$CFG/hosts.tmp"
echo "$NAME $HOST $TOKEN $CLIP_TLS" >> "$CFG/hosts.tmp"
chmod 600 "$CFG/hosts.tmp"
mv "$CFG/hosts.tmp" "$CFG/hosts"
echo "$NAME" > "$CFG/current"

remove_old_block || true

# ---- записать блок ----
# zsh поддерживает тот же синтаксис функций, что и bash, плюс local/case/printf.
# Не называй локальные переменные status/path — в zsh они специальные.

echo "$MARK_BEGIN" >> "$RC"
cat >> "$RC" <<'EOF'
_clip_help='clip — буфер обмена через VPS

Текст:
  clip                       вывести текст из буфера
  clipw <текст>              записать строку в буфер
  echo foo | clipw           записать из stdin
  clipw < file.txt           записать из файла

Файлы:
  clipls                     список файлов с датой и размером
  clipget <name> [dir]       скачать файл (dir по умолчанию: текущая)
  clipput <file>             залить файл в буфер
  clip prune [N] [-y]        оставить N последних файлов (по умолчанию 10)

Серверы:
  clip switch                список профилей и их доступность
  clip switch <имя>          переключиться на другой сервер

Прочее:
  cliphelp, clip -h          показать эту справку'

# читает активный профиль перед каждым запросом — `clip switch` действует
# сразу во всех открытых терминалах
_clip_load() {
  local cfg="${CLIP_CONFIG:-$HOME/.config/clip}" cur n h t tls
  cur=$(cat "$cfg/current" 2>/dev/null)
  if [ -f "$cfg/hosts" ]; then
    while read -r n h t tls; do
      if [ "$n" = "$cur" ]; then
        CLIP_HOST="$h"; CLIP_TOKEN="$t"; CLIP_TLS="$tls"
        return 0
      fi
    done < "$cfg/hosts"
  fi
  echo "clip: активный профиль не найден в $cfg (см. clip switch)" >&2
  return 1
}

_clip_ping() {  # _clip_ping <host> <token> [tls] → строка состояния
  local code
  code=$(curl ${3:-} -s -o /dev/null --max-time 3 -w '%{http_code}' \
              -H "X-Token: $2" "https://$1/raw" </dev/null)
  case "$code" in
    200) echo "✓ доступен" ;;
    403) echo "✗ токен не подходит" ;;
    000) echo "✗ недоступен" ;;
    *)   echo "? HTTP $code" ;;
  esac
}

_clip_fmt() {  # JSON-список файлов из $1 → таблица
  CLIP_DATA="$1" python3 <<'PY'
import json, os, datetime as dt
data = json.loads(os.environ.get("CLIP_DATA") or "[]")
if not data:
    print("(empty)"); raise SystemExit
for f in data:
    t = dt.datetime.fromtimestamp(f["mtime"]).strftime("%m-%d %H:%M")
    print(f'{f["size"]:>10}  {t}  {f["name"]}')
PY
}

_clip_switch() {
  local cfg="${CLIP_CONFIG:-$HOME/.config/clip}" cur n h t tls mark found=""
  cur=$(cat "$cfg/current" 2>/dev/null)
  [ -f "$cfg/hosts" ] || { echo "clip: нет профилей в $cfg — запусти client.sh" >&2; return 1; }
  if [ $# -eq 0 ]; then
    while read -r n h t tls; do
      [ -n "$n" ] || continue
      mark=" "; [ "$n" = "$cur" ] && mark="*"
      printf '%s %-12s %-32s %s\n' "$mark" "$n" "$h" "$(_clip_ping "$h" "$t" "$tls")"
    done < "$cfg/hosts"
    return 0
  fi
  while read -r n h t tls; do
    [ "$n" = "$1" ] && { found=1; break; }
  done < "$cfg/hosts"
  [ -n "$found" ] || { echo "clip: нет профиля '$1' (список: clip switch)" >&2; return 1; }
  echo "$1" > "$cfg/current"
  echo "→ $n (https://$h) $(_clip_ping "$h" "$t" "$tls")"
}

_clip_prune() {
  local keep=10 yes="" resp ans
  while [ $# -gt 0 ]; do
    case "$1" in
      -y|--yes) yes=1 ;;
      -h|--help) cliphelp; return ;;
      ""|*[!0-9]*) echo "usage: clip prune [N] [-y]" >&2; return 2 ;;
      *) keep="$1" ;;
    esac
    shift
  done
  _clip_load || return 1
  if [ -z "$yes" ]; then
    resp=$(curl $CLIP_TLS -fsS -X POST -H "X-Token: $CLIP_TOKEN" \
                "https://$CLIP_HOST/prune?keep=$keep&dry=1") || return 1
    [ "$resp" = "[]" ] && { echo "нечего удалять (файлов не больше $keep)"; return 0; }
    echo "будут удалены с $CLIP_HOST:"
    _clip_fmt "$resp"
    printf 'удалить? [y/N] '
    read -r ans
    case "$ans" in y|Y|д|Д) ;; *) echo "отмена"; return 0 ;; esac
  fi
  resp=$(curl $CLIP_TLS -fsS -X POST -H "X-Token: $CLIP_TOKEN" \
              "https://$CLIP_HOST/prune?keep=$keep") || return 1
  echo "удалено:"
  _clip_fmt "$resp"
}

cliphelp() {
  echo "$_clip_help"
  _clip_load 2>/dev/null && echo "
Активный сервер и веб-интерфейс: https://$CLIP_HOST"
}

clip() {
  case "${1:-}" in
    -h|--help) cliphelp; return ;;
    switch) shift; _clip_switch "$@"; return ;;
    prune)  shift; _clip_prune "$@"; return ;;
  esac
  _clip_load || return 1
  curl $CLIP_TLS -fsS -H "X-Token: $CLIP_TOKEN" "https://$CLIP_HOST/raw"; echo
}

clipw() {
  case "${1:-}" in -h|--help) cliphelp; return ;; esac
  _clip_load || return 1
  if [ $# -gt 0 ]; then
    printf '%s' "$*" | curl $CLIP_TLS -fsS -X PUT --data-binary @- \
      -H "X-Token: $CLIP_TOKEN" "https://$CLIP_HOST/raw"
  else
    curl $CLIP_TLS -fsS -X PUT --data-binary @- \
      -H "X-Token: $CLIP_TOKEN" "https://$CLIP_HOST/raw"
  fi
}

clipls() {
  case "${1:-}" in -h|--help) cliphelp; return ;; esac
  _clip_load || return 1
  local resp
  resp=$(curl $CLIP_TLS -fsS -H "X-Token: $CLIP_TOKEN" "https://$CLIP_HOST/files") || return 1
  _clip_fmt "$resp"
}

clipget() {
  case "${1:-}" in -h|--help|"") cliphelp; return ;; esac
  _clip_load || return 1
  local name="$1" dest="${2:-.}"
  mkdir -p "$dest"
  curl $CLIP_TLS -fsS -H "X-Token: $CLIP_TOKEN" -o "$dest/$name" \
    "https://$CLIP_HOST/file/$name" && echo "→ $dest/$name"
}

clipput() {
  case "${1:-}" in -h|--help|"") cliphelp; return ;; esac
  _clip_load || return 1
  curl $CLIP_TLS -fsS -H "X-Token: $CLIP_TOKEN" -F "file=@$1" "https://$CLIP_HOST/upload"
  echo
}
EOF
echo "$MARK_END" >> "$RC"

echo
echo "✓ clip установлен в $RC, профиль '$NAME' активен"
echo
echo "примени:"
echo "  source $RC"
echo
echo "проверь:"
echo "  cliphelp"
echo "  clip switch"
