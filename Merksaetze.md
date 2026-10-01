# Merksätze — PostgreSQL & Patroni HA-Lab

Alle wichtigen Hinweise, Merksätze und Praxis-Lehren an einem Ort — automatisch aus den Merke-Kästen des Tutorials gesammelt und um Hinweise aus den Lern-Sitzungen ergänzt. Gedacht zum schnellen Wiederholen vor einem Bewerbungsgespräch; die ausführlichen Fragen mit Antworten stehen in [`Kontrollfragen.md`](Kontrollfragen.md).

## Teil 13 — Backup & Recovery

- **Merksatz fürs Gespräch:** Replikation ≠ Backup. Replikation schützt vor *Ausfall*, Backup schützt vor *Fehlern und Katastrophen*.

- **Merksatz:** Umzug oder neue PostgreSQL-Version → **logisch** (das Rezept nimmt man mit in jede Küche). Schnelle 1:1-Kopie derselben Instanz → **physisch** (das Foto passt nur in dieselbe Küche).

- **Konsequenz:** Ohne WAL-Archivierung kommt man im Ernstfall nur auf den Backup-Zeitpunkt zurück — alles danach ist verloren. Base Backup allein = Standbild. Base Backup + WAL = Video mit Rückspulfunktion.

- **Ein Backup ist kein Backup bis du es erfolgreich restored hast.**

- **Bei einem Patroni-Cluster verwaltet Patroni die PostgreSQL-Konfiguration zentral über etcd — nicht über die lokale `patroni.yml`.**

- **Lerneffekt fürs echte Admin-Leben:** Bei Patroni ändert man PostgreSQL-Parameter grundsätzlich über `patronictl edit-config` — niemals direkt per `ALTER SYSTEM` oder in der `postgresql.conf`. Und man muss wissen, welche Parameter nur einen Reload und welche einen echten Restart brauchen.

- **Merksatz:** Bei einem Patroni-Cluster fasst man PostgreSQL nie direkt an (kein `ALTER SYSTEM`, kein `systemctl`). Immer über Patroni: `edit-config`, `restart`, `switchover`. Der Dirigent muss die Kontrolle behalten.

- **Merke:** Der `archive_command` muss auf **jedem** Knoten funktionieren (inklusive existierendem Zielverzeichnis). Da durch Failover jeder Knoten zum Leader werden kann, muss das Archiv-Verzeichnis überall vorhanden sein — sonst schlägt nach einem Failover die Archivierung auf dem neuen Leader fehl.

- **Merke:** `failed_count` ist ein historischer Zähler (wird nicht zurückgesetzt). Entscheidend ist nicht, dass er mal > 0 war, sondern dass er **nicht weiter steigt**, während `archived_count` klettert.

## Teil 14 — Performance-Analyse mit pgbench

- **Praxis-Stolperstein (live erlebt):** `createdb` auf einer Replica scheitert mit `cannot execute CREATE DATABASE in a read-only transaction`. Eine Replica nimmt keine Schreibbefehle an. Vor Schreibaktionen also immer `patronictl list` prüfen, wer aktuell Leader ist — der Leader kann durch Failover gewechselt haben. (Genau dieses Problem löst später HAProxy/VIP automatisch.)

- **Kernprinzip — Durchsatz und Latenz ziehen gegeneinander:** Mehr parallele Last → der Server schafft insgesamt mehr (höhere TPS), aber der Einzelne wartet länger (höhere Latenz). Es gibt einen *Sweet Spot*, ab dem mehr Clients die TPS nicht weiter steigern, sondern nur noch die Latenz explodieren lassen.

- **Admin-Lehre:** Den Sweet Spot suchen — die Client-Zahl mit maximaler TPS, *bevor* die Latenz unzumutbar wird. Wer darüber hinaus skalieren will, muss die **Hardware** aufstocken (mehr Kerne), nicht die Client-Zahl.

- **Lerneffekt:** Ein Benchmark ist nur so gut wie seine Methodik. Nur eine Variable pro Schritt ändern, den Lastgenerator nicht selbst zum Engpass werden lassen, und ihn möglichst getrennt vom Messobjekt betreiben.

- **HA-Benchmark-Lehre:** In einem Cluster mit wanderndem Leader beeinflusst die **Position des Lastgenerators relativ zum Leader** die Messung massiv. Läuft der Generator auf demselben Knoten wie der Leader, konkurrieren beide um dieselben CPUs (langsamer). Läuft er auf einem anderen Knoten, sind die Ressourcen getrennt (schneller). Wer im HA-Umfeld benchmarkt, muss den Leader-Zustand kennen und protokollieren — sonst misst er Zufall statt Leistung.

## Teil 15 — Query-Analyse mit EXPLAIN und EXPLAIN ANALYZE

- **Merke:** Bei `SELECT` ist `EXPLAIN ANALYZE` harmlos. Bei `INSERT` / `UPDATE` / `DELETE` gehört es in einen `BEGIN … ROLLBACK`-Block. **Immer.**

- **Faustregel:** Ab etwa **5–10 % der Tabelle** wird ein Seq Scan günstiger als ein Index Scan. Bei 50 % ist das keine Diskussion mehr.

- **Merke:** Indizes lohnen sich nur für **selektive** Bedingungen. Viele Treffer → Seq Scan. Wenige Treffer → Index Scan.

- **Dass ein Index existiert, heißt nicht, dass er benutzt wird.** Der Planner entscheidet pro Query neu, ob sich der Umweg über den Index lohnt. Ein Index für unselektive Bedingungen ist reine Schreiblast (er muss bei jedem `INSERT`/`UPDATE`/`DELETE` mitgepflegt werden) ohne jeden Lesevorteil — genau deshalb ist "einfach überall Indizes drauf" kein Tuning, sondern das Gegenteil davon.

- **Merksatz:** keepalived macht den Eingang hochverfügbar, Patroni macht die Datenbank hochverfügbar.

- **Merksatz:** Ein führendes `%` macht jeden B-Tree-Index unbrauchbar. `LIKE 'Smith%'` kann einen Index nutzen, `LIKE '%Smith%'` nicht.

- **Merke:** Vor der Suche nach komplizierten Ursachen die Voraussetzungen prüfen. `\di` (Indizes) und `\d tabelle` sind dafür die schnellsten Werkzeuge.

- **Merke:** Bei einer sprachabhängigen Collation wie `de_DE.UTF-8` braucht eine Präfix-Suche mit `LIKE 'abc%'` einen Index mit `text_pattern_ops`. Gleiche Abfrage, gleiche Daten: Allein die Art des Index entscheidet, ob er nutzbar ist.

- **Merksatz:** Ob ein Index benutzt wird, hängt an zwei Bedingungen. Er muss für die Abfrage *technisch nutzbar* sein (Collation, führendes `%`), und er muss sich *lohnen* (Selektivität).

## Teil 16 — VIP, DNS und der Ausfalltest des VIP-Halters

- **Praxis-Regel:** Zum Administrieren immer die festen Adressen `.201`–`.203` nutzen. Die `.200` ist für Anwendungen gedacht (Port `5000` → HAProxy).

- **Merksatz:** Drei echte Rechner, vier Adressen. Die vierte wandert.

- **Merksatz:** Hochverfügbarkeit ist nur so stark wie das schwächste Glied der Kette — und DNS übersieht man leicht.

- **Merksatz:** Ein laufender Dienst sagt nichts über seinen Autostart. Ein HA-Cluster ist erst getestet, wenn jeder Knoten einen Neustart überlebt hat.

## Teil 17 — Monitoring mit Prometheus und Grafana

- **Merkregel:** Was in der **Datenbank** steht (Rollen, Passwörter, Tabellen), macht man einmal auf dem Leader. Was in einer **Datei auf dem Knoten** steht, macht man auf jedem Knoten selbst.

- **Pull-Prinzip:** Prometheus baut die Verbindung auf, die Knoten schicken nichts von sich aus. Fehlt eine Metrik, prüft man zuerst vom Monitor aus, ob er den Port erreicht.

- **Anwendung vs. Monitoring:** Anwendungen verbinden sich über die VIP (sie sollen nicht wissen, wer Leader ist). Monitoring verbindet sich direkt mit jedem Knoten (es *will* jeden einzeln sehen). Über die VIP würden alle Exporter nur den Leader messen.

- **Least Privilege:** Der Exporter bekommt eine eigene Login-Rolle mit `pg_monitor` (Statistiken lesen, keine Tabelleninhalte, keine Schreibrechte) — nie den Superuser `postgres`.

- **`\password` statt `ALTER ROLE … PASSWORD '…'`:** fragt verdeckt ab, schickt das Passwort gehasht — kein Klartext in psql-History und Server-Log.

- **`curl` antwortet ≠ Daten fließen:** Eine Antwort auf Port 9187 heißt nur, dass der Exporter läuft. Erst `pg_up 1` heißt, dass er in die Datenbank kommt. Alarmiert wird auf `pg_up == 0`.

- **Basiseinheiten:** Prometheus-Metriken stehen immer in Basiseinheiten (Bytes, Sekunden), die Einheit steckt im Namen (`_bytes`, `_seconds`). Umgerechnet wird erst in Grafana.

- **gauge vs. counter:** gauge = aktueller Stand (steigt und fällt). counter = zählt nur hoch; interessant ist erst die Steigung über `rate()`.

- **Auch Prometheus hat ein WAL:** gleiches Prinzip wie PostgreSQL — erst ins Log, dann in die Datenbank; nach einem Absturz wird das WAL nachgespielt.

- **Wessen `localhost`?** Grafana fragt Prometheus serverseitig ab, nicht dein Browser. Deshalb ist `http://localhost:9090` als Datenquelle richtig, obwohl du Grafana vom Mac aus öffnest. Adressen immer aus der Perspektive dessen lesen, der die Verbindung aufbaut.

- **Monitoring zeigt Stichproben, keinen Film:** Was zwischen zwei Scrapes (15 s) passiert, ist unsichtbar. Ein Failover erscheint als harter Sprung; durch gestaffelte Scrapes kann `patroni_primary` kurz zwei oder null Leader zeigen — Messartefakt, kein Split-Brain. Für kurze Ereignisse sind die Logs die Wahrheit (`patronictl history`).

- **Alarme auf Symptome, nicht auf Kurven:** Nur alarmieren, was Handeln erfordert (kein/zwei Leader, `pg_up == 0`, WAL-Archiv scheitert). Alarme mit Wartezeit (`for: 1m`), sonst lösen Scrape-Artefakte Fehlalarme aus. Zu viele Alarme = Alarm-Müdigkeit.

- **Monitoring im Großen = drei Ebenen:** Alarm ruft den Menschen → Übersicht zeigt *wo* → Detail-Dashboard zeigt *warum*. Niemand schaut Dashboards zu, solange nichts passiert.

- **Werkseinstellungen erkennen:** `shared_buffers = 128 MiB` auf 4 GB RAM heißt „nie getunt“. Startwert ≈ 25 % RAM; Änderung über `patronictl edit-config`, braucht Restart.

- **Restart-Parameter im Cluster rollierend anwenden:** `patronictl edit-config` → `patronictl restart` Knoten für Knoten, Replicas zuerst, Leader zuletzt bzw. per Switchover. Der Cluster bleibt durchgehend erreichbar.

## Betrieb & Werkzeuge

- **Patroni-Knoten nie einfach rebooten:** Ist er Leader, vorher `patronictl switchover`, sonst gibt es einen unnötigen Failover.

- **`systemctl` vs. `patronictl`:** Die eiserne Regel gilt für PostgreSQL selbst. Dienste, die Patroni nicht kennt (Exporter, Prometheus, Grafana), startet man normal mit `systemctl`.

- **Pre-Commit-Hook meldet Secrets:** Treffer erst mit eigenen Augen prüfen. Nur bei echten Fehlalarmen bewusst `git commit --no-verify` — nie aus Bequemlichkeit.

- **`git diff` zeigt keine neuen Dateien:** Es vergleicht nur Dateien, die Git schon kennt. Neue (untracked) Dateien sieht man mit `git status`.

- **Nicht existierende systemd-Unit:** `systemctl is-active tippfehler` meldet nur `inactive`, keinen Fehler. Tab-Vervollständigung nutzen.
