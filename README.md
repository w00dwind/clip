# Clip — Удаленный буфер обмена

Утилита для быстрой передачи текста и файлов через VPS.

**Веб-интерфейс:** [https://aeza.frn.dedyn.io:8443](https://aeza.frn.dedyn.io:8443)

---
## Установка клиента
```bash
curl -L https://raw.githubusercontent.com/w00dwind/clip/refs/heads/main/client.sh | sh
source ~/.bashrc
```

На вопрос `CLIP_HOST` жми Enter (по умолчанию `aeza.frn.dedyn.io:8443`).
Сертификат валидный (Let's Encrypt) — клиент проверяет TLS, браузер не ругается.

Если поднимаешь свой сервер по IP / на self-signed — ставь с `CLIP_TLS="-k" sh client.sh`
(клиент пойдёт с `curl -k`), в браузере будет предупреждение → «Дополнительно → Перейти».

### Несколько серверов (переезд при блокировках)

Каждый запуск установщика добавляет профиль сервера в `~/.config/clip/hosts`
(строка `имя host token [tls]`) и делает его активным. Второй сервер:

```bash
CLIP_HOST=other.example.org:8443 CLIP_NAME=other sh client.sh
```

```bash
clip switch          # список профилей, активный помечен *, плюс проверка доступности
clip switch other    # переключиться — действует сразу во всех открытых терминалах
```

Данные на серверах раздельные: текст и файлы с одного на другой не переносятся.




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
# (для домена: -subj "/CN=cpbrd.duckdns.org" -addext "subjectAltName=DNS:cpbrd.duckdns.org")

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

---

## 📋 Команды

### Работа с текстом
| Команда | Описание |
| :--- | :--- |
| `clip` | Вывести содержимое текста из буфера |
| `clipw <текст>` | Записать строку в буфер |
| `echo foo | clipw` | Записать данные из конвейера (stdin) |
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
| `cliphelp` | Показать справку |
| `clip -h` | Альтернативный вызов справки |

---

## 💡 Примеры использования

**Получение ссылки и скачивание:**
```bash
URL=$(clip); curl -O "$URL"
