# Stolpersteine — Probleme aus Aufbau und Betrieb

Alle Probleme, die beim Aufbau und Betrieb dieses Clusters tatsächlich aufgetreten sind, je mit Ursache und Lösung. Die ausführliche Herleitung mit Logs und Befehlen steht jeweils im verlinkten Abschnitt des [Tutorials](../PostgreSQL_und_Patroni_Tutorial.md).

Format: **Symptom → Ursache → Lösung**

---

## Aufbau des Clusters

| Symptom | Ursache | Lösung | Details |
|---|---|---|---|
| etcd-Knoten finden sich nicht | Listen- und Advertise-Adresse verwechselt: `127.0.0.1` als Advertise-Adresse bedeutet für die anderen Knoten „ich selbst“ | Advertise immer auf die im Netz erreichbare IP setzen, Listen darf zusätzlich `127.0.0.1` enthalten | [Teil 8](../PostgreSQL_und_Patroni_Tutorial.md#listen-vs-advertise--der-typische-stolperstein) |
| HAProxy auf node1 gestoppt, die VIP bleibt trotzdem dort | Positives `weight 20` im `vrrp_script`: Fällt der Check aus, sinkt die Priorität nur von 170 auf 150, immer noch höher als 100 und 90 | `weight` weglassen: Bei Script-Fehler geht die Instanz in den FAULT-Zustand und gibt die VIP ab | [Teil 12, Bug 1](../PostgreSQL_und_Patroni_Tutorial.md#bug-1-positives-weight-verhindert-den-failover-komplett) |
| keepalived startet ohne Fehlermeldung, der Health-Check ist aber tot | `enable_script_security` sucht den System-User `keepalived_script`, den es nicht gab; der Track-Script-Block wird still entfernt | System-User anlegen (`useradd --system … keepalived_script`) | [Teil 12, Bug 2](../PostgreSQL_und_Patroni_Tutorial.md#bug-2-enable_script_security-sucht-einen-user-den-es-nicht-gibt) |
| Check-Script wird deaktiviert („not executable for uid 999“) | Script stand aus einer früheren Härtungsrunde auf `chmod 700` | `chmod 755`: root schreibt, alle anderen lesen und führen aus | [Teil 12, Bug 3](../PostgreSQL_und_Patroni_Tutorial.md#bug-3-falsche-dateiberechtigung-blockiert-den-neuen-user) |
| Nach einem Failover scheitert die WAL-Archivierung (`failed_count` steigt) | Das Archiv-Verzeichnis existierte nur auf dem alten Leader, nicht auf node2 | Verzeichnis auf **allen** Knoten anlegen; Kontrolle über `pg_stat_archiver` | [Teil 13.5](../PostgreSQL_und_Patroni_Tutorial.md#archiv-verzeichnis-muss-auf-allen-knoten-existieren) |
| `git push` abgelehnt („fetch first“) | Auf GitHub lagen bereits Commits (README/Lizenz), lokal nicht vorhanden | Erst holen und zusammenführen, dann pushen | [Teil 7, Exkurs](../PostgreSQL_und_Patroni_Tutorial.md#exkurs-git--fetch-first-beim-ersten-push-ins-github-repo) |

## Betrieb und Patchen

| Symptom | Ursache | Lösung | Details |
|---|---|---|---|
| Nach dem Neustart eines Knotens läuft Patroni nicht | Patroni-Autostart war auf allen Knoten deaktiviert | `systemctl enable patroni`, per Neustart-Test bestätigt | [Teil 16.4](../PostgreSQL_und_Patroni_Tutorial.md#164-der-eigentliche-fund-patroni-startet-nach-dem-neustart-nicht) |
| `/etc/patroni.yml` mit Passwörtern für alle lesbar | Standard-Dateirechte nach dem Anlegen | `root:postgres`, Modus `640` | [Teil 16.5](../PostgreSQL_und_Patroni_Tutorial.md#165-nebenfund-patroniyml-war-für-alle-lesbar) |
| `apt upgrade` auf dem Leader löst einen ungeplanten Failover aus | `needrestart` startet `patroni.service` nach dem Update automatisch neu | Rollierend patchen: erst Replicas, den Leader vorher per `patronictl switchover` abgeben | [Teil 17.10](../PostgreSQL_und_Patroni_Tutorial.md#stolperstein-1-needrestart-startet-patroni-neu) |
| Knoten laufen nach dem Patchen mit unterschiedlichen Kernel-Versionen | Phased Updates von Ubuntu verteilen Pakete zeitversetzt | Kernel-Versionen nach jedem Patchlauf vergleichen | [Teil 17.10](../PostgreSQL_und_Patroni_Tutorial.md#stolperstein-2-kernel-drift-zwischen-den-knoten) |
| Tippfehler in einem Parameter fällt erst später auf | `patronictl edit-config` übernimmt, was im Diff steht | Diff vor dem Bestätigen lesen, danach mit `SHOW` prüfen | [Teil 17.11](../PostgreSQL_und_Patroni_Tutorial.md#stolperstein-tippfehler-im-diff) |
| `patronictl`: „config file … not existing or no read rights“ | Folge der eigenen Härtung: `/etc/patroni.yml` ist `root:postgres 640`, der Login-User steht in keiner der Gruppen | `sudo patronictl …`; den User **nicht** in die Gruppe `postgres` aufnehmen, sonst ist die Härtung weich | [Teil 17.9](../PostgreSQL_und_Patroni_Tutorial.md#stolperstein-patronictl-ohne-sudo) |
| etcd-Neustart löst einen Leader-Wechsel aus | `patroni.service` hing per `Requires=etcd.service` hart an etcd | `Wants=` statt `Requires=`; etcd-Neustart ohne Leader-Wechsel nachgewiesen | [Teil 17.15](../PostgreSQL_und_Patroni_Tutorial.md#punkt-6--requires--wants-etcd-wartung-ohne-leader-wechsel) |
| Root-Partition bei rund 70 % | Zu kleine Disk für OS, Datenbank, WAL-Archiv und Logs | Inventur der Belegung, `lvextend` im laufenden Betrieb auf allen Knoten (9,8 → 18 GB) | [Teil 17.3](../PostgreSQL_und_Patroni_Tutorial.md#befund-die-root-partition-läuft-voll) |
| SSH-Rundgang-Skript: `Permission denied (publickey,password)` | Zwei Ursachen nacheinander: altes Schloss in `authorized_keys`, danach Passphrase auf dem Schlüssel | Fingerabdrücke vergleichen, `ssh-copy-id` vom richtigen Rechner, Passphrase entfernen | [Teil 18.4](../PostgreSQL_und_Patroni_Tutorial.md#184-stolpersteine-live-25102026-zwei-fehler-hintereinander) |

## Ausfälle und Incidents

| Symptom | Ursache | Lösung | Details |
|---|---|---|---|
| Nach dem Failover unter Last hängt eine Replica in „starting“ | WAL-Lücke: Checkpoint mitten im Lasttest, `wal_keep_size` 0, Archiv nur lokal; `pg_rewind` fand die nötigen WAL-Dateien nicht mehr | `patronictl reinit`; danach `wal_keep_size` 1 GB als Reserve, mit einem zweiten Ausfall unter Last nachgewiesen (Rückkehr ohne Eingriff) | [Teil 17.13](../PostgreSQL_und_Patroni_Tutorial.md#befund-ph-node2-bleibt-in-starting-hängen--die-wal-lücke) |
| Leader-Platte 100 % voll, etcd auf demselben Knoten beendet sich | Lokales WAL-Archiv ohne Aufbewahrungsregel (11 GB nach zwei Tagen Lasttests) | Gezielt im Archiv aufgeräumt; Panel „Plattenbelegung“ gebaut; zentrales Archiv mit Aufbewahrung (pgBackRest) als nächster Schritt | [Teil 17.14](../PostgreSQL_und_Patroni_Tutorial.md#incident-während-der-nachher-messung-platte-voll-auf-dem-leader-20102026-1108) |
| Exporter meldet alle 15 s `ERROR: recovery is in progress` auf den Replicas | Die Slot-Abfrage des Exporters nutzt `pg_current_wal_lsn()`, das auf einer Replica nicht erlaubt ist | Bekannt und harmlos, begründet zurückgestellt (ein schneller Fix hätte zwei Panels die Datenquelle genommen) | [Teil 17.15](../PostgreSQL_und_Patroni_Tutorial.md#punkt-7--error-recovery-is-in-progress-auf-den-replicas) |

## Monitoring und Messen

| Symptom | Ursache | Lösung | Details |
|---|---|---|---|
| Ampel zeigt „grün“, obwohl kein Leader da ist | Grafanas Standard-Schwellen (Base grün, 80 rot) | Schwellen bewusst setzen und gegen den Rohwert prüfen, nicht gegen die formatierte Anzeige | [Teil 17.12](../PostgreSQL_und_Patroni_Tutorial.md#1712-eigenes-ha-dashboard) |
| Panels zeigen nach einem Ausfall „Geister“ (letzter Wert eines toten Knotens) | Zeitreihen-Abfrage statt Momentaufnahme | Instant-Queries für Fragen wie „Wer ist jetzt Leader?“ | [Teil 17.13](../PostgreSQL_und_Patroni_Tutorial.md#1713-failover-unter-last) |
| Negativer Replikations-Lag im Dashboard | Leader und Replica werden nicht im selben Moment abgetastet | Als Messartefakt einordnen, nicht als Fehler | [Teil 17.13](../PostgreSQL_und_Patroni_Tutorial.md#stolperstein-negativer-lag--nicht-gleichzeitige-abtastung) |
| Benchmark-Ergebnis über die VIP unplausibel | Lastgenerator und Leader konkurrieren um dieselben CPUs | Gegenprobe vom getrennten Lastgenerator `ph-monitor`; Leader-Position zu jedem Lauf protokollieren | [Teil 14.5](../PostgreSQL_und_Patroni_Tutorial.md#die-überraschende-zahl--und-wie-man-sie-sauber-auflöst) |

## SQL und Query-Analyse

| Symptom | Ursache | Lösung | Details |
|---|---|---|---|
| `EXPLAIN ANALYZE DELETE …` löscht wirklich | `ANALYZE` führt die Query aus, um echte Messwerte zu liefern | Schreibende Queries nur in `BEGIN … ROLLBACK` analysieren | [Teil 15](../PostgreSQL_und_Patroni_Tutorial.md#teil-15--query-analyse-mit-explain-und-explain-analyze) |
| `LIKE 'abc%'` nutzt den Index nicht | Collation `de_DE.UTF-8` erlaubt keinen Präfix-Vergleich über den normalen B-Tree-Index | Index mit `text_pattern_ops` | [Teil 15, Praxis II](../PostgreSQL_und_Patroni_Tutorial.md#schritt-3-die-ursache-ist-die-collation) |
