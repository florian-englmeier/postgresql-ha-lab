# Betriebslog — PostgreSQL HA Lab

Jede Änderung am Cluster bekommt hier eine Zeile: wann, welcher Knoten, was, warum, mit welchem Ergebnis. Die Systemprotokolle (`/var/log/apt/history.log`, `patronictl history`, `journalctl -u patroni`) zeigen, *was* passiert ist. Dieses Log hält fest, *warum*, und verbindet zusammengehörige Schritte.

Neueste Einträge oben. Zeiten in UTC, wo sie aus Systemausgaben stammen. Details stehen im jeweils verlinkten Tutorial-Teil.

---

## Laufend geführt (ab 02.10.2026)

| Datum | Knoten | Aktion | Grund | Ergebnis | Doku |
|---|---|---|---|---|---|
| 02.10.2026 | ph-node2 | `apt upgrade` + Reboot auf Kernel 6.8.0-146 | letzter Knoten des rollierenden Patchens | Replica `streaming`, Lag 0, alle drei Knoten einheitlich | Teil 17.10 |
| 02.10.2026 | ph-node2 → ph-node1 | `patronictl switchover` | ph-node2 (Leader) sollte gepatcht werden | TL 8 → 9, kein Failover | Teil 17.10 |
| 02.10.2026 | ph-node1 | `apt upgrade` (Kernel 146 nachgezogen) + Reboot | Kernel-Drift: node1 hatte 146 beim ersten Upgrade nicht bekommen | Replica `streaming` | Teil 17.10 |
| 02.10.2026 | ph-node3 | `apt upgrade` + Reboot (07:26:04 UTC) | Patchen als frische Replica | Kernel 6.8.0-146, nach 9 s wieder `streaming` | Teil 17.10 |
| 02.10.2026 07:18:49 UTC | ph-node3 → ph-node2 | `patronictl switchover` | ph-node3 (Leader) sollte gepatcht werden | TL 7 → 8, kein Failover | Teil 17.10 |
| 02.10.2026 | ph-node1, ph-node2 | `apt upgrade` | 28 ausstehende Updates; `needrestart` startete Patroni auf beiden Replicas automatisch neu | beide Replicas wieder `streaming` | Teil 17.10 |
| 02.10.2026 | ph-node2 | Reboot | Kernel 6.8.0-142 installiert, aber nicht aktiv | Replica `streaming`, TL 7 unverändert | Teil 17.8 |

---

## Nachgetragen (aus Tutorial und `patronictl history`, 16.09.–01.10.2026)

Rekonstruiert aus den datierten Ergebnissen im Tutorial. Was dort nicht belegt ist, steht hier auch nicht.

| Datum | Knoten | Aktion | Grund | Ergebnis | Doku |
|---|---|---|---|---|---|
| 01.10.2026 | ph-monitor | Grafana: Datenquelle Prometheus, Dashboards 1860 und 9628 | Monitoring sichtbar machen | Daten aller drei Knoten; Befund: `shared_buffers` auf Werkseinstellung | Teil 17.7 |
| 01.10.2026 | ph-node1–3 | `/etc/patroni.yml` auf `root:postgres 640` | Datei enthielt Passwörter und war weltlesbar | gehärtet; `patronictl` braucht seitdem `sudo` | Teil 16.5 |
| 01.10.2026 | ph-node1–3 | `systemctl enable patroni` | Autostart war deaktiviert, Fund beim Ausfalltest | per Neustart-Test bestätigt | Teil 16.4 |
| 01.10.2026 | Pi-hole | DNS-Eintrag `pg-vip.home.arpa` → VIP | stabiler Name statt IP | Kette Name → VIP → HAProxy → Leader verifiziert | Teil 16.2 |
| 30.09.–01.10.2026 | ph-monitor, ph-node1–3 | Monitoring-VM angelegt, node_exporter, postgres_exporter (`pg_monitor`-Rolle), Prometheus | Monitoring-Unterbau | 11/11 Ziele `UP` | Teil 17.1–17.6 |
| 22.09.2026 | ph-node2 | Archiv-Verzeichnis `/var/lib/postgresql/wal_archive` angelegt | nach Leader-Wechsel 567 fehlgeschlagene Archivierungen | `archived_count` 0 → 51 | Teil 13.5 |
| 21.09.2026 | Cluster | `archive_mode = on`, `archive_command` per `patronictl edit-config`, Restart | WAL-Archivierung für PITR | Archivierung läuft | Teil 13.5 |
| 17.09.2026 | ph-node1–3 | keepalived, VIP 192.168.178.200 | stabiler Einstiegspunkt | VIP gebunden, Failover-Test erfolgreich | Teil 11–12 |
| 17.09.2026 | ph-node1–3 | HAProxy auf Port 5000 | Routing zum aktuellen Leader | `pg_is_in_recovery() = f` über HAProxy | Teil 10 |
| 17.09.2026 | ph-node1–3 | Patroni-Cluster gestartet | HA-Cluster aufbauen | ph-node1 Leader, zwei Replicas, Lag 0 | Teil 9 |
| 16.09.2026 | ph-node1–3 | etcd-3-Knoten-Cluster | Konsens-Store für Patroni | alle Member `started`, Health-Check OK | Teil 8 |

### Leader-Wechsel laut `patronictl history`

| Ende von TL | Zeitpunkt (UTC) | Neuer Leader | Ursache |
|---|---|---|---|
| 1 | 21.09.2026 07:38 | ph-node3 | nicht dokumentiert |
| 2 | 22.09.2026 06:01 | ph-node2 | nicht dokumentiert |
| 3 | 23.09.2026 06:09 | ph-node1 | nicht dokumentiert |
| 4 | 23.09.2026 06:46 | ph-node3 | nicht dokumentiert |
| 5 | 26.09.2026 06:36 | ph-node2 | nicht dokumentiert |
| 6 | 01.10.2026 06:47 | ph-node3 | nicht dokumentiert |
| 7 | 02.10.2026 07:18 | ph-node2 | geplanter Switchover (Patchen) |
| 8 | 02.10.2026 | ph-node1 | geplanter Switchover (Patchen) |

Sechs der acht Wechsel haben keine dokumentierte Ursache. Genau diese Lücke soll das Log künftig schließen. Auffällig: Die ungeklärten Wechsel liegen fast alle morgens zwischen 06:00 und 06:50 UTC.
