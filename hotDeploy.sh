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

# Sprawdzenie, czy Docker jest zainstalowany
if ! command -v docker >/dev/null 2>&1; then
  echo "Błąd: Docker nie jest zainstalowany!"
  exit 1
fi

# Sprawdzenie wersji Dockera
DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' | cut -d'-' -f1)
MIN_VERSION="28.0.0"

version_ge() {
  [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]
}

if ! version_ge "$DOCKER_VERSION" "$MIN_VERSION"; then
  echo "Błąd: Wymagana wersja Dockera to przynajmniej $MIN_VERSION. Obecna wersja: $DOCKER_VERSION"
  exit 1
fi

# Wybór polecenia docker compose
if docker compose version >/dev/null 2>&1; then
  DOCKER_COMPOSE="docker compose"
else
  echo "Błąd: 'docker compose' nie jest dostępne. Upewnij się, że masz Dockera w wersji 28+."
  exit 1
fi

# Unikalny komentarz crona, by uniknąć duplikatów
CRON_TAG="# AUTO_COMPOSE_UPDATER"
CRON_CMD="*/$INTERVAL * * * * \"$SCRIPT_PATH\" \"$REPO_URL\" \"$CLONE_DIR\" \"$INTERVAL\" \"$WATCH_DIRS\" >> /tmp/compose_cron.log 2>&1 $CRON_TAG"

(
  crontab -l 2>/dev/null | grep -v "$CRON_TAG"
  echo "$CRON_CMD"
) | crontab -

# Klonowanie repozytorium, jeśli nie istnieje
if [ ! -d "$CLONE_DIR" ]; then
  echo "Klonuję repozytorium do '$CLONE_DIR'..."
  mkdir -p "$CLONE_DIR"
  git clone "$REPO_URL" "$CLONE_DIR"
fi

cd "$CLONE_DIR" || exit 1

# Sprawdzenie, czy to repozytorium Git
if [ ! -d ".git" ]; then
  echo "Katalog '$CLONE_DIR' nie jest repozytorium Git!"
  exit 1
fi

# Wykrycie domyślnej gałęzi
DEFAULT_BRANCH=$(git remote show origin | awk '/HEAD branch/ {print $NF}')

# Pobranie zmian bez mergowania
git fetch origin "$DEFAULT_BRANCH"

# Zbieranie zmienionych plików
CHANGED_FILES=$(git diff HEAD origin/"$DEFAULT_BRANCH" --name-only)

# Aktualizacja lokalnego repo
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/"$DEFAULT_BRANCH")

if [ "$LOCAL" != "$REMOTE" ]; then
  echo "Zmiany w repozytorium – aktualizuję..."
  git pull origin "$DEFAULT_BRANCH"
else
  echo "Brak zmian w repozytorium (HEAD = $LOCAL)"
fi

# Przetwarzanie katalogów aplikacji
IFS=',' read -ra DIRS <<<"$WATCH_DIRS"
for dir in "${DIRS[@]}"; do
  APP_DIR="$CLONE_DIR/$dir"
  COMPOSE_FILE="$APP_DIR/compose.yml"
  MARKER_FILE="$APP_DIR/.first_run_marker"

  if [ -d "$APP_DIR" ]; then
    if [ ! -f "$MARKER_FILE" ]; then
      echo "Nowa aplikacja '$dir'. Pierwsze uruchomienie..."
      if [ -f "$COMPOSE_FILE" ]; then
        $DOCKER_COMPOSE -f "$COMPOSE_FILE" up -d --build --force-recreate
        touch "$MARKER_FILE"
      else
        echo "Brak pliku compose.yml w '$dir'"
      fi
      continue
    fi

    if echo "$CHANGED_FILES" | grep -q "^$dir/compose.yml"; then
      echo "Zmieniono compose.yml w '$dir'. Aktualizuję kontenery..."
      $DOCKER_COMPOSE -f "$COMPOSE_FILE" up -d --build --force-recreate
    else
      echo "Brak zmian w '$dir'"
    fi
  else
    echo "Katalog '$dir' nie istnieje w repozytorium!"
  fi
done
