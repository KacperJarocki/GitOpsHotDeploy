#!/bin/bash

# Sprawdzanie liczby argumentów
if [ $# -ne 4 ]; then
  echo "Użycie: $0 <repo_url> <katalog_docelowy> <co_ile_minut> <katalogi_do_obserwacji (np. appka1,appka2)>"
  exit 1
fi

REPO_URL=$1
CLONE_DIR=$(eval echo $2)
INTERVAL=$3
WATCH_DIRS=$4
SCRIPT_PATH=$(realpath "$0")

# Dodanie do crona (jeśli jeszcze nie ma)
CRON_CMD="*/$INTERVAL * * * * $SCRIPT_PATH $REPO_URL $CLONE_DIR $INTERVAL $WATCH_DIRS >> /tmp/compose_cron.log 2>&1"
(
  crontab -l 2>/dev/null | grep -Fv "$SCRIPT_PATH"
  echo "$CRON_CMD"
) | crontab -

# Klonowanie jeśli repo nie istnieje
if [ ! -d "$CLONE_DIR" ]; then
  echo "Klonuję repozytorium do '$CLONE_DIR'..."
  mkdir -p "$CLONE_DIR"
  git clone "$REPO_URL" "$CLONE_DIR"
fi

cd "$CLONE_DIR" || exit

# Sprawdzenie czy katalog jest repozytorium Git
if [ ! -d ".git" ]; then
  echo "Katalog '$CLONE_DIR' nie jest repozytorium Git!"
  exit 1
fi

# Pobieranie zmian
git fetch origin

LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main)

if [ "$LOCAL" != "$REMOTE" ]; then
  echo "Są zmiany, sprawdzam różnice..."

  CHANGED_FILES=$(git diff --name-only HEAD origin/main)

  IFS=',' read -ra DIRS <<<"$WATCH_DIRS"
  for dir in "${DIRS[@]}"; do
    if echo "$CHANGED_FILES" | grep -q "^$dir/"; then
      echo "Zmiany w katalogu '$dir'. Wykonuję docker compose..."

      if [ -f "$CLONE_DIR/$dir/compose.yml" ]; then
        docker compose -f "$CLONE_DIR/$dir/compose.yml" up --no-deps
      else
        echo "Brak pliku compose.yml w katalogu '$dir'"
      fi
    else
      echo "Brak zmian w '$dir'"
    fi
  done

  git pull origin main
else
  echo "Brak zmian w repozytorium."
fi
