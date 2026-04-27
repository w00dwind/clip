clip — буфер обмена через VPS (https://cpbrd.duckdns.org:8443)

Текст:
  clip                       вывести текст из буфера
  clipw <текст>              записать строку в буфер
  echo foo | clipw           записать из stdin
  clipw < file.txt           записать из файла

Файлы:
  clipls                     список файлов в буфере
  clipget <name> [dir]       скачать файл (dir по умолчанию: текущая)
  clipput <file>             залить файл в буфер

Прочее:
  cliphelp, clip -h          показать эту справку
  Веб-интерфейс:             https://cpbrd.duckdns.org:8443

Примеры:
  URL=$(clip); curl -O "$URL"
  clip | xargs git clone
  sudo journalctl -u airflow-scheduler -n 500 --no-pager | clipw
  clipget my_dag.py ~/airflow/dags/
