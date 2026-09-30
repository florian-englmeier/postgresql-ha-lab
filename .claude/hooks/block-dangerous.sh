#!/usr/bin/env bash
# PreToolUse-Hook für Bash: blockiert Befehle, die Patroni umgehen oder
# Secrets ins Repo bringen. Exit 2 = blockieren, stderr geht an Claude zurück.
input="$(cat)"
cmd="$(printf '%s' "$input" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null)"
[ -z "$cmd" ] && exit 0

block() { echo "BLOCKIERT durch block-dangerous.sh: $1" >&2; exit 2; }

# Patroni umgehen
echo "$cmd" | grep -Eqi 'systemctl[[:space:]]+(start|stop|restart|reload|kill)[[:space:]]+postgresql' \
  && block "PostgreSQL wird von Patroni verwaltet. Nutze 'patronictl restart/reload postgres-ha <node>'."
echo "$cmd" | grep -Eqi 'pg_ctl[^|;&]*/var/lib/postgresql/16/patroni' \
  && block "Kein pg_ctl auf dem Patroni-Datenverzeichnis. Nutze patronictl."
echo "$cmd" | grep -Eqi 'alter[[:space:]]+system' \
  && block "Kein ALTER SYSTEM im Patroni-Cluster. Nutze 'patronictl edit-config'."
echo "$cmd" | grep -Eqi 'rm[[:space:]]+-[a-z]*r[a-z]*[[:space:]].*/var/lib/(postgresql|etcd)' \
  && block "Löschen von PostgreSQL-/etcd-Daten nur manuell durch Flo."
echo "$cmd" | grep -Eqi 'patronictl[^|;&]*[[:space:]](remove|reinit)([[:space:]]|$)' \
  && block "patronictl remove/reinit ist destruktiv – nur manuell durch Flo."

# Secrets / Git
echo "$cmd" | grep -Eqi 'git[[:space:]]+add[^|;&]*[[:space:]](-f|--force)' \
  && block "git add --force könnte gitignorte Secrets committen."
echo "$cmd" | grep -Eqi 'git[[:space:]]+commit[^|;&]*--no-verify' \
  && block "--no-verify umgeht den Secret-Check im pre-commit-Hook."

exit 0
