# postgresql-ha-lab

Lernprojekt: hochverfügbarer 3-Knoten-PostgreSQL-Cluster auf Proxmox
(PostgreSQL 16 + etcd + Patroni + HAProxy + keepalived). Das Repo enthält
Configs, Skripte und das Tutorial (Lernprotokoll). Ziel ist Verständnis:
Erklärungen sind genauso wichtig wie funktionierende Befehle.

## Topologie

| Knoten   | VMID | IP              |
|----------|------|-----------------|
| ph-node1 | 201  | 192.168.178.201 |
| ph-node2 | 202  | 192.168.178.202 |
| ph-node3 | 203  | 192.168.178.203 |
| VIP      | –    | 192.168.178.200 |

Ubuntu 24.04, 2 vCPU / 4 GB je Knoten. Patroni-Scope: `postgres-ha`.
Datenverzeichnis: `/var/lib/postgresql/16/patroni`, Config: `/etc/patroni.yml`.

| Port | Dienst |
|------|--------|
| 5432 | PostgreSQL (direkt, lauscht NUR auf der Knoten-IP, nicht 127.0.0.1) |
| 5000 | HAProxy → aktueller Leader (für Anwendungen immer VIP:5000) |
| 7000 | HAProxy-Stats |
| 8008 | Patroni REST-API (`/primary` = 200 nur auf dem Leader) |
| 2379 / 2380 | etcd Client / Peer |

## Eiserne Regeln (nie brechen)

- PostgreSQL wird von Patroni verwaltet. **Nie** `systemctl start/stop/restart postgresql*`,
  **nie** `pg_ctl` auf dem Patroni-Datenverzeichnis, **nie** `ALTER SYSTEM`,
  **nie** die `postgresql.conf` von Hand editieren.
- Cluster-Parameter ändern: `patronictl -c /etc/patroni.yml edit-config`.
  `bootstrap.dcs` in der patroni.yml wirkt nur beim allerersten Start.
- Restart-Parameter (z.B. `archive_mode`, `shared_buffers`, `max_connections`)
  → `patronictl restart postgres-ha <node>`; Reload-Parameter → `patronictl reload`.
- Rollenwechsel nur per `patronictl switchover` / `failover`.
- Der Leader wandert. Vor jeder Schreibaktion `patronictl list` prüfen –
  oder über VIP:5000 gehen.
- Alles, was der Leader braucht (z.B. `/var/lib/postgresql/wal_archive`),
  muss auf ALLEN drei Knoten existieren.
- Experimente (PITR, Restore-Tests) nur auf isolierten Instanzen (eigener Port,
  eigenes Datenverzeichnis), nie auf einer Patroni-Instanz.

## Secrets

Passwörter stehen **nie** im Repo. Im Repo liegen nur `*.example`-Dateien mit
Platzhaltern. Echte Werte liegen lokal in `configs/patroni/patroni.env`
(gitignored) bzw. auf den Knoten in `/etc/patroni/patroni.env`.
Keine Passwörter in Doku, Commit-Messages oder Befehlsbeispielen – Platzhalter
wie `<REPLICATION_PASSWORD>` verwenden.

## Arbeitsweise

- Diagnosen nachweisen, nicht behaupten: Befehl + Ausgabe zeigen
  (`patronictl list`, `pg_stat_archiver`, `ss -tlnp`, Logfiles).
- Bei Benchmarks Leader-Zustand und Parameter protokollieren, nur eine
  Variable pro Schritt ändern.
- Standard-Gesundheitscheck: Skill `/cluster-healthcheck`.
- Tutorial-Stil: siehe `.claude/rules/doku-stil.md`.
