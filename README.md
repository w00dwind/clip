# Clip — Удаленный буфер обмена

Утилита для быстрой передачи текста и файлов через VPS: веб-интерфейс плюс
shell-команды (`clip`, `clipw`, `clipput`, …) для bash и zsh.

Развёрнуто два независимых сервера — на случай блокировки одного из них:

| Профиль | Адрес / веб-интерфейс |
| :--- | :--- |
| `aeza` | [https://aeza.frn.dedyn.io:8443](https://aeza.frn.dedyn.io:8443) |
| `cncgbw` | [https://cpbrd.duckdns.org:8443](https://cpbrd.duckdns.org:8443) |

Данные на серверах раздельные: текст и файлы с одного на другой не переносятся.

---
## Установка клиента

```bash
curl -L https://raw.githubusercontent.com/w00dwind/clip/refs/heads/main/client.sh -o /tmp/client.sh
CLIP_HOST=cpbrd.duckdns.org:8443 CLIP_NAME=cncgbw sh /tmp/client.sh
CLIP_HOST=aeza.frn.dedyn.io:8443 CLIP_NAME=aeza   sh /tmp/client.sh
source ~/.bashrc   # или ~/.zshrc
```

Установщик спросит токен, проверит соединение и запишет:

- **профиль сервера** в `~/.config/clip/hosts` (права 600) — строка `имя host token [tls]`;
  активный профиль — в `~/.config/clip/current`. Активным становится тот,
  что установлен последним;
- **блок с командами** в `~/.bashrc` или `~/.zshrc` (токена в rc-файле нет).

Нужен только один сервер — достаточно `curl -L …/client.sh | sh`: на вопрос
`CLIP_HOST` жми Enter (по умолчанию `aeza.frn.dedyn.io:8443`).

Параметры установщика:

| Параметр | Назначение |
| :--- | :--- |
| `CLIP_HOST`, `CLIP_TOKEN` | адрес и токен сервера (иначе спросит) |
| `CLIP_NAME` / `--name` | имя профиля (по умолчанию — первая метка домена) |
| `CLIP_TLS="-k"` | не проверять сертификат — для сервера по IP / на self-signed |
| `--shell bash\|zsh`, `--rc <файл>` | куда писать блок с командами |
| `--uninstall` | убрать блок из rc-файла (профили в `~/.config/clip` остаются) |

Оба сервера отдают валидный сертификат Let's Encrypt — клиент проверяет TLS,
браузер не ругается. С `CLIP_TLS="-k"` в браузере будет предупреждение →
«Дополнительно → Перейти».

### Переключение между серверами

```bash
clip switch          # список профилей, активный помечен *, плюс проверка доступности
clip switch cncgbw   # переключиться — действует сразу во всех открытых терминалах
```

Ещё один сервер добавляется повторным запуском установщика с другими
`CLIP_HOST` и `CLIP_NAME`; запуск с существующим именем обновляет профиль.

---

## 📋 Команды

### Работа с текстом
| Команда | Описание |
| :--- | :--- |
| `clip` | Вывести содержимое текста из буфера |
| `clipw <текст>` | Записать строку в буфер |
| `echo foo \| clipw` | Записать данные из конвейера (stdin) |
| `clipw < file.txt` | Записать содержимое файла в буфер |

### Работа с файлами
| Команда | Описание |
| :--- | :--- |
| `clipls` | Показать список файлов в хранилище |
| `clipget <name> [dir]` | Скачать файл (по умолчанию в текущую директорию) |
| `clipput <file>` | Загрузить файл в буфер |
| `clip prune [N] [-y]` | Оставить N последних файлов (по умолчанию 10), остальные удалить. Спрашивает подтверждение, `-y` — без вопроса |

### Серверы
| Команда | Описание |
| :--- | :--- |
| `clip switch` | Список профилей и их доступность |
| `clip switch <имя>` | Переключиться на другой сервер |

### Помощь
| Команда | Описание |
| :--- | :--- |
| `cliphelp` | Показать справку и адрес активного сервера |
| `clip -h` | Альтернативный вызов справки |

Все команды работают с сервером активного профиля.

---

## 🧹 Очистка файлов

- **Автоматически.** После каждой загрузки сервер удаляет файлы, которые
  одновременно не входят в `CLIP_KEEP` самых новых **и** старше `CLIP_KEEP_DAYS`
  дней (по умолчанию 10 и 7). Пачка свежих файлов не пострадает, старьё уходит само.
- **Вручную.** `clip prune [N]` оставляет ровно N последних файлов независимо
  от возраста.

Удаление безвозвратное. Текст буфера очистка не затрагивает.

---

## 💡 Примеры использования

**Получение ссылки и скачивание:**
```bash
URL=$(clip); curl -O "$URL"
```

**Передать файл с одной машины на другую:**
```bash
clipput report.pdf            # на первой
clipget report.pdf ~/Downloads   # на второй
```

**Основной сервер заблокирован:**
```bash
clip switch            # видно, какой сервер недоступен
clip switch cncgbw
```

---

## Разворачивание на сервере

```bash
# 1. Зависимости
sudo apt update && sudo apt install -y python3-venv git
sudo git clone https://github.com/w00dwind/clip /opt/clip
sudo python3 -m venv /opt/clip/venv
sudo /opt/clip/venv/bin/pip install flask gunicorn

# 2. Хранилище
sudo mkdir -p /var/lib/clip/files

# 3. TLS — self-signed. Без домена подставь IP сервера:
IP=1.2.3.4
sudo openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout /etc/ssl/private/clip.key -out /etc/ssl/certs/clip.crt \
  -subj "/CN=$IP" -addext "subjectAltName=IP:$IP"
# (для домена: -subj "/CN=example.org" -addext "subjectAltName=DNS:example.org",
#  либо сертификат Let's Encrypt)

# 4. systemd-юнит
sudo tee /etc/systemd/system/clip.service >/dev/null <<'EOF'
[Unit]
After=network.target

[Service]
Environment=CLIP_TOKEN=ЗАМЕНИ_НА_СВОЙ_ТОКЕН
# автоочистка: после загрузки удаляются файлы, которые не входят в CLIP_KEEP
# самых новых И старше CLIP_KEEP_DAYS дней. CLIP_KEEP=0 — выключить.
Environment=CLIP_KEEP=10
Environment=CLIP_KEEP_DAYS=7
WorkingDirectory=/opt/clip
ExecStart=/opt/clip/venv/bin/gunicorn -b 0.0.0.0:8443 \
  --certfile /etc/ssl/certs/clip.crt --keyfile /etc/ssl/private/clip.key app:app
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 5. Запуск
sudo systemctl daemon-reload && sudo systemctl enable --now clip
sudo ufw allow 8443/tcp
```

Проверка: `curl -k https://<server>:8443/raw -H "X-Token: <токен>"`

Обновление: `cd /opt/clip && sudo git pull && sudo systemctl restart clip`

Вместо TLS в gunicorn можно поставить перед ним nginx: gunicorn слушает
`127.0.0.1:<порт>` без сертификата, nginx терминирует TLS и проксирует на него.

### Переменные окружения сервера

| Переменная | По умолчанию | Назначение |
| :--- | :--- | :--- |
| `CLIP_TOKEN` | — (обязательна) | токен доступа |
| `CLIP_DATA` | `/var/lib/clip` | каталог с текстом буфера и файлами |
| `CLIP_KEEP` | `10` | сколько новых файлов автоочистка не трогает; `0` — выключить |
| `CLIP_KEEP_DAYS` | `7` | файлы моложе этого срока автоочистка не трогает |

### HTTP API

Авторизация — заголовок `X-Token`, cookie `token` или параметр `?t=`.

| Метод и путь | Назначение |
| :--- | :--- |
| `GET /raw`, `PUT /raw` | прочитать / записать текст |
| `GET /files` | список файлов (JSON: `name`, `size`, `mtime`) |
| `POST /upload` | загрузить файл (multipart, поле `file`, до 64 МБ) |
| `GET /file/<name>` | скачать файл (`?inline=1` — открыть в браузере) |
| `DELETE /file/<name>` | удалить файл |
| `POST /prune?keep=N` | оставить N последних файлов; `&dry=1` — только показать, что удалится |
