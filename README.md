# HestiaCP Site Cloner

Скрипт для быстрого копирования сайта между доменами в HestiaCP с переносом файлов, базы данных и SSL.

---

## 🚀 Возможности

- Копирование файлов сайта через `rsync`
- Автоматическое создание домена в HestiaCP
- Поиск и перенос базы данных (DLE / WordPress)
- Создание новой базы и пользователя
- Дамп и импорт MySQL
- Обновление конфигурации сайта
- Проверка DNS
- Выпуск SSL через Let's Encrypt
- Перезапуск web-сервера

---

## ⚙️ Требования

- HestiaCP
- root доступ к серверу
- bash
- rsync
- mysql / mysqldump
- dig (dnsutils)
- openssl

---

## 📦 Установка

```bash
wget https://raw.githubusercontent.com/Nikolinc/copy-website/main/copy_hestia.sh
cd copy-hestia
chmod +x copy_hestia.sh
