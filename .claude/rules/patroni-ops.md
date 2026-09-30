---
paths:
  - "configs/**"
  - "scripts/**"
  - "**/*.yml"
  - "**/*.yaml"
  - "**/*.cfg"
---
# Regeln für Cluster-Configs und Skripte

- patroni.yml: `bootstrap.dcs` ist nur der Startzettel. Laufende Cluster-Parameter
  leben in etcd → Änderungen per `patronictl edit-config`, nicht in der Datei.
- Knotenspezifische Werte (name, restapi.connect_address, postgresql.connect_address)
  unterscheiden sich pro Knoten. Identisch auf allen: scope, Credentials,
  bootstrap-Block. Die HAProxy-Config ist auf allen Knoten identisch.
- etcd: `ETCD_INITIAL_CLUSTER`, `_STATE`, `_TOKEN` auf allen Knoten identisch;
  Advertise-URLs nie mit 127.0.0.1.
- Credentials in Configs nie hart eintragen. Patroni liest sie aus
  Umgebungsvariablen (PATRONI_SUPERUSER_PASSWORD, PATRONI_REPLICATION_PASSWORD),
  die per systemd `EnvironmentFile=/etc/patroni/patroni.env` gesetzt werden.
- Neue Configs immer als `*.example` mit Platzhaltern anlegen.
- Skripte gegen den Cluster: zuerst read-only prüfen, Schreibaktionen explizit
  bestätigen lassen.
