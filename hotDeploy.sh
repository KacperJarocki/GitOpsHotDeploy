#!/bin/bash

# Sprawdzanie, czy podano wystarczającą liczbę argumentów
if [ $# -ne 2 ]; then
  echo "Użycie: $0 <link_do_repo_z_composem> <katalog_docelowy>"
  exit 1
fi

# Przypisanie argumentów do zmiennych
REPO_URL=$1          # Link do repozytorium z docker-compose
CLONE_DIR=$(echo $2) # Katalog, do którego będzie klonowane lub z którego będą pobierane zmiany

# Rozwiązywanie ścieżki katalogu domowego (~)
CLONE_DIR=$(eval echo $CLONE_DIR)

# Ścieżka do pliku docker-compose.yml
COMPOSE_FILE="$CLONE_DIR/compose.yml"

# Pętla sprawdzająca zmiany co minutę
while true; do
  # Sprawdzenie, czy katalog repozytorium istnieje
  if [ ! -d "$CLONE_DIR" ]; then
    echo "Katalog '$CLONE_DIR' nie istnieje. Tworzę katalog i klonuję repozytorium..."
    mkdir -p "$CLONE_DIR"
    git clone "$REPO_URL" "$CLONE_DIR"
    cd "$CLONE_DIR" || exit
    docker compose -f "$COMPOSE_FILE" up --no-deps
  elif [ ! "$(ls -A $CLONE_DIR)" ]; then
    echo "Katalog '$CLONE_DIR' jest pusty. Wykonuję git pull..."
    cd "$CLONE_DIR" || exit
    git pull origin main # Zmienna 'main' na nazwę gałęzi, jeśli używasz innej
    docker compose -f "$COMPOSE_FILE" up --no-deps
  elif [ -d "$CLONE_DIR/.git" ]; then
    echo "Repozytorium Git istnieje. Wykonuję git fetch..."
    cd "$CLONE_DIR" || exit
    git fetch origin # Pobiera zmiany, ale ich nie łączy
    # Możesz tu również sprawdzić, czy są różnice, jeśli potrzebujesz
    echo "Sprawdzanie zakończone, brak automatycznych zmian."
  else
    echo "Katalog '$CLONE_DIR' nie jest repozytorium Git!"
    exit 1
  fi

  # Opóźnienie o 60 sekund (1 minuta)
  sleep 60
done
