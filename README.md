# Clip — Удаленный буфер обмена

Утилита для быстрой передачи текста и файлов через VPS.

**Веб-интерфейс:** [https://cpbrd.duckdns.org:8443](https://cpbrd.duckdns.org:8443)

---
## Установка клиента
```bash
curl -L https://raw.githubusercontent.com/w00dwind/clip/refs/heads/main/client.sh | sh
source ~/.bashrc
```

На вопрос `CLIP_HOST` можно ответить просто IP-адресом: `1.2.3.4:8443` — домен не нужен.
Сертификат self-signed, поэтому клиент ходит с `curl -k`. Если у тебя валидный
сертификат — ставь с `CLIP_TLS="" sh client.sh` и проверка вернётся.

В браузере на `https://1.2.3.4:8443` будет предупреждение → «Дополнительно → Перейти»,
один раз на профиль.




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
