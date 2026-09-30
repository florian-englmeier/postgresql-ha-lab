---
name: cluster-healthcheck
description: Read-only Gesundheitscheck des Patroni-Clusters postgres-ha (Patroni, etcd, WAL-Archivierung, Replikation, HAProxy/VIP). Nutzen bei "Cluster-Status", "ist alles gesund", nach Failover/Switchover, vor und nach Wartung oder Benchmarks.
---
# Cluster-Healthcheck

Nur lesende Befehle. Nichts neu starten, nichts ändern – Auffälligkeiten
melden und einen Fix vorschlagen, aber erst nach Bestätigung ausführen.
SSH-Ziele: siehe CLAUDE.local.md.

## 1. Patroni – wer ist Leader?
`ssh <node> "patronictl -c /etc/patroni.yml list"`
Prüfen: genau ein Leader, Replicas `streaming`, alle auf derselben Timeline (TL),
Lag ≈ 0, keine `Pending restart`-Flags. Leader-Knoten für die weiteren Schritte merken.

## 2. etcd – Quorum
`ssh <node> "etcdctl endpoint health --cluster && etcdctl member list"`
Prüfen: alle 3 Endpoints healthy, 3 Member `started`.

## 3. WAL-Archivierung – auf dem Leader
`ssh <leader> "sudo -u postgres psql -h <leader-ip> -Atc \"SELECT archived_count, last_archived_wal, last_archived_time, failed_count, last_failed_wal, last_failed_time FROM pg_stat_archiver;\""`
Prüfen: `last_archived_time` aktuell. `failed_count` darf historisch > 0 sein,
aber `last_failed_time` darf nicht jünger sein als `last_archived_time`.
Zusätzlich auf ALLEN Knoten: `ls -ld /var/lib/postgresql/wal_archive` existiert
und gehört postgres.

## 4. Replikation – auf dem Leader
`SELECT application_name, client_addr, state, sync_state, replay_lag FROM pg_stat_replication;`
Prüfen: 2 Einträge, `streaming`.

## 5. HAProxy / VIP
- `curl -s -o /dev/null -w "%{http_code}" http://<ip>:8008/primary` je Knoten →
  genau einmal 200.
- `psql -h 192.168.178.200 -p 5000 -U postgres -Atc "SELECT pg_is_in_recovery();"` → `f`.
- Welcher Knoten hält die VIP: `ssh <node> "ip -br addr | grep 192.168.178.200"`.

## Ausgabe
Kurze Tabelle: Komponente | Status (OK / WARNUNG / FEHLER) | Beleg (1 Zeile).
Darunter nur die Auffälligkeiten mit vermuteter Ursache und vorgeschlagenem Fix.
Leader-Knoten und Timeline immer nennen.
