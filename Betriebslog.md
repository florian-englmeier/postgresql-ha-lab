# Betriebslog — PostgreSQL HA Lab

Jede Änderung am Cluster bekommt hier eine Zeile: wann, welcher Knoten, was, warum, mit welchem Ergebnis. Die Systemprotokolle (`/var/log/apt/history.log`, `patronictl history`, `journalctl -u patroni`) zeigen, *was* passiert ist. Dieses Log hält fest, *warum*, und verbindet zusammengehörige Schritte.

Neueste Einträge oben. Zeiten in UTC, wo sie aus Systemausgaben stammen. Details stehen im jeweils verlinkten Tutorial-Teil.

---

## Laufend geführt (ab 02.10.2026)

| Datum | Knoten | Aktion | Grund | Ergebnis | Doku |
|---|---|---|---|---|---|
| 20.10.2026 09:47:31 | ph-node3 | `qm start 203` nach Ausfall unter Last | Crashtest für `wal_keep_size` | `stopped` → `streaming`, TL 16, Lag 0 nach ~2 min, **ohne `reinit`**. `pg_rewind` zurück auf gemeinsamen Checkpoint (REDO 1/E2000C00), Trennpunkt 2/191013C0 → 55 Segmente ≈ 880 MB Lücke lagen lokal (Streaming vom Leader erst ab 2/19000000). Grenze: Reserve 1 GB knapp; zentrales Archiv bleibt offen | Teil 17.13 |
| 20.10.2026 09:43:25 | ph-node3 → ph-node2 | **Failover unter Last:** pgbench `-c 50 -T 180 -P 5` von ph-monitor, dann `qm stop 203` (Leader) | README-Ziel „Failover unter Last, im Dashboard sichtbar“ | Promote ph-node2 um 09:44:00,751 → **≈ 35 s ohne Leader** (ttl 30 + Wahl); Ampel live „KEIN LEADER“; pgbench: alle 50 Clients aborted, kein Reconnect, 161 731 bestätigte Transaktionen, 0 failed | Teil 17.13 |
| 20.10.2026 09:40:41 | ph-node2 | `qm start 202` | Wiederanlauf nach Failover-Test | ~09:41 `streaming`, TL 15, Lag 0 — ohne `reinit` (kleine WAL-Lücke, da keine Last seit Vortag; noch kein Beweis für `wal_keep_size`) | Teil 17.13 |
| 20.10.2026 09:35:22 | ph-node2 → ph-node3 | `qm stop 202` (Stromausfall Leader) | Failover-Test; pgbench versehentlich nicht gestartet → zweite Nullmessung | **TL 14 → 15**, ph-node3 Leader, ph-node1 `streaming` Lag 0 | Teil 17.13 |
| 19.10.2026 ~15:33 | ph-node1 → ph-node2 | `patronictl switchover` (geplant) | Leader und VIP-Halter (ph-node1) trennen, damit der Failover-Test unter Last nur eine Variable ändert | **TL 13 → 14**, ph-node2 Leader; ph-node1 sofort `streaming`, Lag 0 — ohne Crash-Recovery und ohne `pg_rewind` (sauberer Shutdown-Checkpoint) | Teil 17.13 |
| 19.10.2026 15:23 | Cluster | `patronictl edit-config -p wal_keep_size=1GB` | Schutzschicht nach dem Failover-Befund: Leader soll WAL-Reserve für zurückkehrende Replicas aufheben (Größe ≈ `max_wal_size`) | `show-config` zeigt `wal_keep_size: 1GB`; Reload-Parameter, kein Neustart | Teil 17.13 |
| 19.10.2026 ~12:32 | ph-node2 | `patronictl reinit postgres-ha ph-node2` | ph-node2 hing nach dem Failover in `starting`: `pg_rewind` erfolgreich, danach WAL ab 1/CE (REDO des Checkpoints von 10:27, mitten im Lasttest) nötig; ph-node1 hatte es recycelt (`wal_keep_size` 0), das Segment lag nur im lokalen Archiv von ph-node2, `restore_command` nicht gesetzt | 12:33:37 alle drei Knoten TL 13, `streaming`, Lag 0. Offen: `wal_keep_size`, zentrales WAL-Archiv mit `restore_command`, Panel „Replicas streaming“, Runbook | Teil 17.13 |
| 19.10.2026 12:07–12:15 | ph-node2 → ph-node1 | **Geplanter ungeplanter Failover:** `qm stop 202` (Stromausfall Leader, 12:07:21–:32), Neustart `qm start 202` um 12:12:45 | Failover-Test; pgbench lief versehentlich nicht → Nullmessung im Leerlauf | ph-node1 Leader, **TL 12 → 13**, ph-node3 `streaming` Lag 0; ph-node2 nach Neustart `Replica`/`starting` (Crash-Recovery), Abschluss offen. Nebenbefunde: Leader-Panel zeigt den toten Knoten weiter (letzter Wert im Zeitraum), Lag-Panel seit 12:07 leer | Teil 17.13 |
| 19.10.2026 ~10:26 | ph-monitor → VIP | Gegenprobe pgbench `-c 50 -j 2 -T 60` vom getrennten Lastgenerator | prüfen, ob pgbench auf ph-node1 den Laststufen-Test verfälscht hat | 2 831 TPS, 17,7 ms, 0 Fehler (ph-node1: 2 977 / 16,8 ms) — Unterschied im Rauschen, Werte bleiben gültig. Befund: ph-node1 trägt die VIP (`ip -br a`), HAProxy-Weiterleitung kostet dort ~10 Punkte CPU gegenüber ph-node3. Cache-Hit-Ratio unter Last: Leader ~94 %, Replicas ~97–98 % (Baseline vor `shared_buffers`-Tuning) | Teil 17.12 |
| 19.10.2026 ~10:20 | ph-monitor | pgbench als Lastgenerator installiert: `create_main_cluster = false` in `/etc/postgresql-common/createcluster.conf`, dann `apt install postgresql-16` | pgbench liegt bei Ubuntu im Server-Paket (`dpkg -S` auf ph-node1); ohne die Einstellung legt das Paket automatisch einen Cluster an und startet einen zweiten PostgreSQL-Server | `pgbench --version` 16.15, `pg_lsclusters` leer — Werkzeug ohne Server | Teil 17.12 |
| 19.10.2026 ~10:10 | ph-monitor | **Störung (behoben):** `/` voll (93 %, 671 M frei) — `apt install postgresql-client` zog ausstehende Updates (Grafana 13.2.4, snapd) mit und brach mit „No space left on device“ ab; Prometheus konnte nicht mehr schreiben | ph-monitor war beim `lvextend` der Cluster-Knoten am 12.10. durchgerutscht: `/` nur 9,8 G, 8,22 G ungenutzt in der Volume Group | `lvextend -r -l +100%FREE` → 18 G, 51 % belegt; `dpkg --configure -a` + `apt -f install` → Grafana 13.2.4 fertig installiert; `grafana-server` und `prometheus` active. Lehre: Korrekturen auf alle Systeme gleicher Bauart anwenden; auch der Monitoring-Server braucht Überwachung (Alarm auf Plattenfüllstand). Offen: was außerhalb von `/var` ~6 G belegt | Teil 17.12 |
| 19.10.2026 09:42–09:52 | ph-node1 → VIP | Laststufen-Test pgbench `-c 10/25/50/75 -j 2 -T 60` | Sättigungspunkt mit Live-Dashboard bestimmen | TPS 1 056 / 2 124 / 2 977 / 3 038, Latenz 9,5 / 11,8 / 16,8 / 24,7 ms, 0 Fehler; Sättigung ab ~50 Clients; Engpass auf ph-node2 wandert von iowait (10 Clients) zu CPU (75 Clients, Group Commit); Lag flach, Leader unverändert ph-node2 | Teil 17.12 |
| 19.10.2026 | ph-node1–3 | Platz-Check vor dem Laststufen-Test: `df -h /`, `du -sh /var/lib/postgresql/wal_archive` | viel Schreiblast erzeugt viel WAL, das Archiv wächst mit | `/` belegt: node1 42 % (Archiv 1,1 G), node2 51 % (Archiv 2,4 G, Leader seit 15.10.), node3 38 % (225 M) — ausreichend. Befunde, offen: Archiv liegt lokal auf dem jeweiligen Leader (für PITR verstreut über drei Knoten; Ziel: zentraler Archivspeicher, z. B. NAS/pgBackRest) und hat keine Aufbewahrungsregel | – |
| 19.10.2026 | ph-monitor | Lag-Panel umgebaut: `pg_stat_replication_pg_wal_lsn_diff` statt Differenz zweier Patroni-Scrapes | negativer Lag unter Last (17.10.) war Messartefakt durch nicht gleichzeitiges Scrapen | Verifikation mit zwei pgbench-Läufen (`-c 10 -T 60`): keine negativen Werte, Spitzen-Lag ~125 KB je Replica (`max_over_time`); Leader weiter ph-node2, kein Wechsel im Upgrade-Fenster 18./19.10. | Teil 17.12 |
| 17.10.2026 19:48 | ph-node1 → VIP | Kurzer pgbench-Test: `-c 10 -j 2 -T 60 pgbench_test` | erstes Leben im neuen Dashboard vor dem eigentlichen Lasttest | ~1 500 TPS auf ph-node2, Connections 4 → 14, Cache-Hit-Ratio ph-node2 auf 93,9 % (`shared_buffers` 128 MiB); Lag-Panel zeigt Messartefakt (negativer Lag durch nicht gleichzeitiges Scrapen) → Panel umbauen | Teil 17.12 |
| 17.10.2026 | Cluster | **Lücke geschlossen:** `patronictl history` zeigt drei weitere ungeplante Leader-Wechsel (TL 9–11, siehe Tabelle unten) | Leader war ph-node2, laut Log zuletzt ph-node1 (TL 9) | Muster verschoben: vor dem 02.10. ca. 06:00–06:50 UTC, danach 04:26–04:44 UTC = 06:26–06:44 Ortszeit. Erklärung: Zeitzone der VMs am 02.10. auf Europe/Berlin umgestellt, `apt-daily-upgrade.timer` (06:00 Ortszeit + Zufallsverzögerung) wanderte mit. Verdacht wie TL 6: `unattended-upgrade` → `needrestart` → Patroni-Neustart auf dem Leader. Seit `needrestart` im List-Modus (16.10.) kein Wechsel mehr. Offen: Beleg je Tag in `/var/log/apt/history.log` | – |
| 17.10.2026 | ph-monitor | Doppeltes Dashboard „PostgreSQL HA-Cluster“ (UID `ad5pq6d`, alter Zwischenstand) entdeckt | zwei Dashboards gleichen Namens, Verwechslungsgefahr | gültig ist UID `adv645n` (mit Stern markiert); Duplikat zum Löschen vorgesehen | Teil 17.12 |
| 17.10.2026 | ph-monitor | Eigenes Grafana-Dashboard „PostgreSQL HA-Cluster“ angelegt: Leader-Status, aktueller Leader, Replikations-Lag, Cache-Hit-Ratio, Connections, TPS | Operator-Ampel statt Community-Dashboards; Sensoren für Lasttest und Failover unter Last | alle sechs Panels verifiziert (Leader ph-node2, Lag 0 B, Cache 100 %, je 4 Connections, TPS ~2/3,2); keine Änderung an den Cluster-Knoten | Teil 17.12 |
| 16.10.2026 | ph-monitor | Befund: Zeitzone steht auf `UTC` | laut Eintrag vom 02.10. auf Europe/Berlin umgestellt; beim Vergleich der `date`-Ausgaben aufgefallen (05:55 UTC vs. 07:56 CEST auf den Knoten) | offen: Umstellung prüfen und wiederholen | Teil 17.11 |
| 16.10.2026 | ph-node1–3 | `needrestart` auf List-Modus: `/etc/needrestart/conf.d/50-ha-cluster.conf` mit `$nrconf{restart} = 'l';` | Ursache der ungeklärten morgendlichen Leader-Wechsel (siehe Zeile darunter): automatische Dienst-Neustarts nach `unattended-upgrade` | `needrestart -b` meldet nur noch (dbus, systemd-logind, unattended-upgrades; Kernel 6.8.0-147 installiert, nicht aktiv), startet nichts neu. Sicherheitsupdates laufen weiter automatisch; Neustarts nur noch geplant und rollierend | Postmortem folgt |
| 16.10.2026 | ph-node2 | **Ursachenanalyse** Leader-Wechsel TL 6 (01.10.2026) | sechs Wechsel ohne dokumentierte Ursache, alle morgens 06:00–06:50 UTC | Beleg: `apt/history.log` 06:47:10–11 `unattended-upgrade` aktualisiert `libssl3t64` + `openssl`; `journalctl` 06:47:12 UTC: systemd stoppt gleichzeitig `patroni`, `keepalived`, ssh, networkd, resolved u. a. (Muster von `needrestart`), PostgreSQL `fast shutdown` → Leader-Lock verloren, ph-node3 übernimmt. VIP wanderte mit. etcd nicht betroffen (Go-Binary, lädt keine libssl) | Postmortem folgt |
| 15.10.2026 | ph-monitor | **Störung (behoben):** nach dem Reboot zeigen alle Grafana-Dashboards „datasource not found“ | Grafana 13 aktualisiert beim Start das Prometheus-Plugin (13.2.2 → 13.2.3): alte Version gestoppt, Download von `storage.googleapis.com` scheitert, weil Pi-hole die Domain blockiert (`getent` → `0.0.0.0`/`::`; Quelle laut `pihole -q`: Blockliste *phishing.army extended*) | Domain in Pi-hole v6 freigegeben (`pihole allow storage.googleapis.com`), DNS-Cache geleert, Grafana neu gestartet: Plugin geladen, beide Dashboards wieder aktiv. Offen: Plugin-Auto-Update beim Start abschalten | Postmortem folgt |
| 15.10.2026 | ph-monitor | `apt upgrade` + Reboot | Login-Banner meldete ausstehende Updates und Neustart; kein Cluster-Knoten, daher ohne Switchover | Prometheus und Grafana wieder aktiv, kurze Lücke im Monitoring | – |
| 12.10.2026 | ph-node1, ph-node3 | `lvextend -r -l +100%FREE` wie auf ph-node2 | einheitliche Plattengröße im Cluster | am 15.10. per Prometheus-Abfrage bestätigt: alle drei Knoten 19,1 GB (dezimal, entspricht 18 GiB) | Teil 17.3 |
| 12.10.2026 | ph-node2 | `lvextend -r -l +100%FREE`: Root-FS 9,8 → 18 GB | Root-FS bei 69 %; Inventur: OS 3,1 GB, DB 1,2 GB, WAL-Archiv 0,88 GB, Logs 0,51 GB | 38 % belegt, 11 GB frei, im laufenden Betrieb ohne Neustart | Teil 17.3 |
| 12.10.2026 | ph-node1 | Befund im Grafana-Dashboard: Root-FS 69,5 % belegt | Screenshot für die Doku | am 02.10. noch 53,9 % (ph-node2); Inventur und Erweiterung siehe Zeile darüber | Teil 17.3 |
| 12.10.2026 | ph-monitor | Diagnose: Prometheus-Weboberfläche liefert `404` | Screenshot der Targets für die Doku | Ursache Ubuntu-Paket `+ds` ohne UI; 11/11 Ziele `up` per API und Grafana bestätigt, keine Änderung am System | Teil 17.6 |
| 02.10.2026 | Cluster | `log_timezone` korrigiert (`Europ/Berlin` → `Europe/Berlin`) | Tippfehler im ersten `edit-config`, hätte beim nächsten Neustart den Start verhindert | `SHOW` zeigt `Europe/Berlin`, kein Pending restart | Teil 17.11 |
| 02.10.2026 | Cluster | `timezone` und `log_timezone` auf `Europe/Berlin` per `patronictl edit-config` | PostgreSQL stand weiter auf `Etc/UTC` | per Reload übernommen, kein Neustart nötig | Teil 17.11 |
| 02.10.2026 | ph-node1, ph-node3, ph-monitor | `timedatectl set-timezone Europe/Berlin` (ph-node2 war es bereits) | Zeitzonen waren zwischen den VMs uneinheitlich | alle vier VMs auf Europe/Berlin, NTP synchron | Teil 17.11 |
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
| 6 | 01.10.2026 06:47 | ph-node3 | **ungeplant:** `unattended-upgrade` (libssl) → `needrestart` startet Patroni auf dem Leader ph-node2 neu (Analyse 16.10.2026) |
| 7 | 02.10.2026 07:18 | ph-node2 | geplanter Switchover (Patchen) |
| 8 | 02.10.2026 07:51 | ph-node1 | geplanter Switchover (Patchen) |
| 9 | 09.10.2026 04:26 | ph-node3 | **ungeplant**, Verdacht `unattended-upgrade` → `needrestart` (06:26 Ortszeit; Beleg offen) |
| 10 | 09.10.2026 04:34 | ph-node1 | **ungeplant**, nur 8 min nach TL 9 — vermutlich derselbe Upgrade-Lauf (Beleg offen) |
| 11 | 15.10.2026 04:44 | ph-node2 | **ungeplant**, Verdacht wie TL 9 (06:44 Ortszeit; Beleg offen) |

**Lesehilfe (19.10.2026):** Jede Zeile von `patronictl history` beschreibt das **Ende** einer Timeline — Zeile 11 heißt „TL 11 endet, ph-node2 startet TL 12“. Die aktuelle Timeline ist also immer *letzte Zeile + 1* und steht in `patronictl list` (Stand 19.10.2026: **TL 12**, Leader ph-node2 seit 15.10.). Kurz verwechselt beim Gesundheitscheck vor dem Failover-Test: `list` zeigte 12, die History endet bei 11 — kein neuer Wechsel, nur die Zählweise.

Sechs der acht Wechsel hatten zunächst keine dokumentierte Ursache. Auffällig: Sie liegen fast alle morgens zwischen 06:00 und 06:50 UTC, genau im Fenster von `apt-daily-upgrade.timer` (06:00 Ortszeit + bis zu 60 min Zufall; die Knoten liefen damals auf UTC). Für TL 6 ist die Kette am 16.10.2026 belegt: `unattended-upgrade` → `needrestart` → Neustart von Patroni auf dem Leader. TL 1–5 sind sehr wahrscheinlich dieselbe Ursache, der Nachweis im jeweiligen `apt/history.log` steht noch aus. Seit 16.10.2026 startet `needrestart` auf den Knoten keine Dienste mehr automatisch neu.

**Nachtrag 17.10.2026:** `patronictl history` zeigt drei weitere ungeplante Wechsel (TL 9–11) — jetzt um 04:26–04:44 UTC. Das ist dasselbe Fenster, nur in Ortszeit: Seit der Zeitzonen-Umstellung am 02.10.2026 rechnet `apt-daily-upgrade.timer` in Europe/Berlin, 06:26–06:44 Ortszeit. Damit liegen neun von elf Wechseln ungeplant im Upgrade-Fenster; geplant waren nur TL 7 und 8. Belege in `apt/history.log` stehen für TL 9–11 noch aus.
