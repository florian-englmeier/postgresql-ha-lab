#!/usr/bin/env bash
# Git pre-commit-Hook: verhindert Commits mit Klartext-Passwörtern.
# Installation (einmalig im Repo):
#   ln -sf ../../scripts/pre-commit-secrets.sh .git/hooks/pre-commit
# Nur hinzugefügte Zeilen werden geprüft; dieses Skript selbst ist ausgenommen
# (sonst findet das Suchmuster sich selbst).
pattern='(password[[:space:]]*[:=][[:space:]]*[^<[:space:]#]|PASSWORD=[^<[:space:]]|PASSWORD[[:space:]]+.[^<]|auth_pass[[:space:]]+[^<[:space:]])'
hits="$(git diff --cached -U0 --no-color -- . ':(exclude)scripts/pre-commit-secrets.sh' \
        | grep -E '^\+[^+]' | grep -Ei "$pattern")"
files="$(git diff --cached --name-only --diff-filter=ACMR \
        | grep -E '(\.env$|/patroni\.yml$|\.pgpass$)' | grep -v '\.example$')"
if [ -n "$hits" ] || [ -n "$files" ]; then
  echo "❌ Commit abgebrochen – mögliche Secrets gefunden:" >&2
  [ -n "$files" ] && echo "Dateien: $files" >&2
  [ -n "$hits" ]  && echo "$hits" >&2
  echo "Platzhalter wie <REPLICATION_PASSWORD> verwenden." >&2
  exit 1
fi
exit 0
