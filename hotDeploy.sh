#!/bin/bash

# Sprawdzanie liczby argumentów
if [ $# -ne 4 ]; then
  echo "Użycie: $0 <repo_url> <katalog_docelowy> <co_ile_minut> <appka1,appka2,...>"
  exit 1
fi

REPO_URL=$1
CLONE_DIR=$(eval echo $2)
INTERVAL=$3
WATCH_DIRS=$4
SCRIPT_PATH=$(realpath "$0")

# Dodanie do crona (jeśli jeszcze nie ma)
CRON_CMD="*/$INTERVAL * * * * $SCRIPT_PATH \"$REPO_URL\" \"$CLONE_DIR\" \"$INTERVAL\" \"$WATCH_DIRS\" >> /tmp/compose_cron.log 2>&1"
(
  crontab -l 2>/dev/null | grep -Fv "$SCRIPT_PATH"
  echo "$CRON_CMD"
) | crontab -

# Klonowanie repozytorium, jeśli nie istnieje
if [ ! -d "$CLONE_DIR" ]; then
  echo "Klonuję repozytorium do '$CLONE_DIR'..."
  mkdir -p "$CLONE_DIR"
  git clone "$REPO_URL" "$CLONE_DIR"
fi

cd "$CLONE_DIR" || exit

# Sprawdzenie, czy to repozytorium Git
if [ ! -d ".git" ]; then
  echo "Katalog '$CLONE_DIR' nie jest repozytorium Git!"
  exit 1
fi

# Pobranie zmian bez mergowania
git fetch origin

# Zbieramy zmienione pliki przed pull
CHANGED_FILES=$(git diff HEAD origin/main --name-only)

# Aktualizacja lokalnego repo
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main)

if [ "$LOCAL" != "$REMOTE" ]; then
  echo "Zmiany w repozytorium – aktualizuję..."
  git pull origin main
else
  echo "Brak zmian w repozytorium (HEAD = $LOCAL)"
fi

# Sprawdzenie aplikacji z listy
IFS=',' read -ra DIRS <<<"$WATCH_DIRS"
for dir in "${DIRS[@]}"; do
  APP_DIR="$CLONE_DIR/$dir"
  COMPOSE_FILE="$APP_DIR/compose.yml"
  MARKER_FILE="$APP_DIR/.first_run_marker"

  if [ -d "$APP_DIR" ]; then
    if [ ! -f "$MARKER_FILE" ]; then
      echo "Nowa aplikacja '$dir'. Pierwsze uruchomienie..."
      if [ -f "$COMPOSE_FILE" ]; then
        docker compose -f "$COMPOSE_FILE" up -d --build --force-recreate
        touch "$MARKER_FILE"
      else
        echo "Brak pliku compose.yml w '$dir'"
      fi
      continue
    fi

    if echo "$CHANGED_FILES" | grep -q "^$dir/compose.yml"; then
      echo "Zmieniono compose.yml w '$dir'. Aktualizuję kontenery..."
      docker compose -f "$COMPOSE_FILE" up -d --build --force-recreate
    else
      echo "Brak zmian w '$dir'"
    fi
  else
    echo "Katalog '$dir' nie istnieje w repozytorium!"
  fi
done
