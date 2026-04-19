#!/usr/bin/env bash

set -e

escape_sed() {
  printf '%s' "$1" | sed 's/[\/&|]/\\&/g'
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --old) OLD="$2"; shift 2 ;;
    --new) NEW="$2"; shift 2 ;;
    --user) USER="$2"; shift 2 ;;
    *) echo "Unknown param: $1"; exit 1 ;;
  esac
done

USER=${USER:-admin}

if [[ -z "$OLD" || -z "$NEW" ]]; then
  echo "Usage: $0 --old old.com --new new.com [--user admin]"
  exit 1
fi

OLD_PATH="/home/$USER/web/$OLD/public_html"
NEW_PATH="/home/$USER/web/$NEW/public_html"

OLD_PHP=$(v-list-web-domain "$USER" "$OLD" | awk '/BACKEND/ {print $2}')
OLD_PROXY=$(v-list-web-domain "$USER" "$OLD" | awk '/PROXY/ {print $2}')
OLD_IP=$(v-list-web-domain "$USER" "$OLD" | awk -F': ' '/^IP:/ {print $2}' | xargs)

echo "[1] Check/create domain"
if ! v-list-web-domain "$USER" "$NEW" >/dev/null 2>&1; then
  v-add-web-domain "$USER" "$NEW" "$OLD_IP" "$OLD_PROXY" "no" "$OLD_PHP"
fi

echo "[2] Copy files"
mkdir -p "$NEW_PATH"
rsync -a "$OLD_PATH/" "$NEW_PATH/" || exit 1

echo "[3] Fix permissions"
chown -R "$USER:$USER" "/home/$USER/web/$NEW/"

echo "[4] Detect DB config"

CONFIG_FILE=""

if [[ -f "$NEW_PATH/engine/data/dbconfig.php" ]]; then
  CONFIG_FILE="$NEW_PATH/engine/data/dbconfig.php"
elif [[ -f "$NEW_PATH/wp-config.php" ]]; then
  CONFIG_FILE="$NEW_PATH/wp-config.php"
elif [[ -f "$NEW_PATH/dbconfig.php" ]]; then
  CONFIG_FILE="$NEW_PATH/dbconfig.php"
else
  CONFIG_FILE=$(grep -rl --include="*.php" "DB_NAME\|DB_USER\|DB_PASSWORD" "$NEW_PATH" 2>/dev/null | head -n 1 || true)
fi

OLD_DB_NAME=""
OLD_DB_USER=""
OLD_DB_PASS=""

if [[ -n "$CONFIG_FILE" ]]; then
  echo "Found config: $CONFIG_FILE"

  # DLE (define)
  if [[ "$CONFIG_FILE" == *"dbconfig.php" ]]; then
    OLD_DB_NAME=$(grep 'DBNAME' "$CONFIG_FILE" | sed -E 's/.*"DBNAME", *"([^"]+)".*/\1/')
    OLD_DB_USER=$(grep 'DBUSER' "$CONFIG_FILE" | sed -E 's/.*"DBUSER", *"([^"]+)".*/\1/')
    OLD_DB_PASS=$(grep 'DBPASS' "$CONFIG_FILE" | sed -E 's/.*"DBPASS", *"([^"]+)".*/\1/')
  # WordPress
  elif [[ "$CONFIG_FILE" == *"wp-config.php" ]]; then
    OLD_DB_NAME=$(grep "DB_NAME" "$CONFIG_FILE" | sed -E "s/.*'([^']+)'.*/\1/")
    OLD_DB_USER=$(grep "DB_USER" "$CONFIG_FILE" | sed -E "s/.*'([^']+)'.*/\1/")
    OLD_DB_PASS=$(grep "DB_PASSWORD" "$CONFIG_FILE" | sed -E "s/.*'([^']+)'.*/\1/")
  fi
fi

if [[ -n "$OLD_DB_NAME" && -n "$OLD_DB_USER" && -n "$OLD_DB_PASS" ]]; then
  echo "[5] Dump DB: $OLD_DB_NAME"
  DUMP_FILE="/tmp/${OLD_DB_NAME}_$$.sql"
  mysqldump -uroot "$OLD_DB_NAME" > "$DUMP_FILE" || echo "Dump failed"

  echo "[6] Create new DB"
  NEW_DB_NAME="${NEW//./_}"
  NEW_DB_USER="$NEW_DB_NAME"
  NEW_DB_PASS=$(openssl rand -base64 12)

  v-add-database "$USER" "$NEW_DB_NAME" "$NEW_DB_USER" "$NEW_DB_PASS"

  REAL_DB_NAME="${USER}_${NEW_DB_NAME}"

  echo "New DB credentials"
  echo "DB_USER: $REAL_DB_NAME"
  echo "DB_PASS: $NEW_DB_PASS"

  echo "[7] Import DB"
  mysql -uroot "$REAL_DB_NAME" < "$DUMP_FILE"  || echo "Import failed"

  echo "[8] Update config"

  OLD_DB_PASS_ESC=$(escape_sed "$OLD_DB_PASS")
  NEW_DB_PASS_ESC=$(escape_sed "$NEW_DB_PASS")

  sed -i "s|$OLD_DB_NAME|$REAL_DB_NAME|g" "$CONFIG_FILE"
  sed -i "s|$OLD_DB_USER|$REAL_DB_NAME|g" "$CONFIG_FILE"
  sed -i "s|$OLD_DB_PASS_ESC|$NEW_DB_PASS_ESC|g" "$CONFIG_FILE"
else
  echo "DB config not found or parse failed, skip DB"
fi

echo "[9] Check DNS"
IP=$(dig +short A "$NEW" | head -n1)

if [[ -n "$IP" ]]; then
  echo "DNS OK: $IP"

  echo "[10] Issue SSL"
  v-add-letsencrypt-domain "$USER" "$NEW" || echo "SSL failed"
else
  echo "DNS not ready, skip SSL"
fi

echo "[11] Restart web"
v-restart-web

echo "DONE"