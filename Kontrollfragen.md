# Kontrollfragen — PostgreSQL & Patroni (Gesamtsammlung)

Stand: 01.10.2026 · zusammengestellt aus dem Tutorial und allen bisherigen Sessions

Nach **Themen** sortiert, nicht nach Teil-Nummern. Ergänzt die Schnell-Referenzen am Ende der einzelnen Tutorial-Teile. Gedacht zum Selbstabfragen: Frage lesen, eigene Antwort überlegen, dann vergleichen.

---

## A. PostgreSQL-Grundlagen

**F: Was ist bei PostgreSQL ein „Cluster"?**
Eine einzelne laufende PostgreSQL-Instanz auf einer Maschine, mit einem Data Directory. Hat nichts mit mehreren Servern oder HA zu tun.

**F: Kann eine Verbindung mehrere Datenbanken gleichzeitig nutzen?**
Nein. Eine Verbindung hängt an genau einer Datenbank. Wechseln heißt neue Verbindung (oder Erweiterungen wie `dblink`).

**F: Was liegt in PGDATA?**
`base/` (Tabellen/Indizes, ein Unterordner pro DB), `pg_wal/` (WAL-Segmente), `postmaster.pid`. Bei Debian/Ubuntu liegen `postgresql.conf` und `pg_hba.conf` dagegen unter `/etc/postgresql/16/main/`.

**F: Wichtigster Architektur-Unterschied zu MySQL?**
MySQL hat austauschbare Storage-Engines (MyISAM, InnoDB). PostgreSQL hat genau eine feste Engine nach dem MVCC-Prinzip.

**F: Was passiert bei einem `UPDATE` unter MVCC?**
Die Zeile wird nicht überschrieben. Es wird eine neue Version geschrieben, die alte als veraltet markiert. Leser und Schreiber blockieren sich so nicht gegenseitig.

**F: Was sind „dead tuples" und wer räumt sie auf?**
Veraltete Zeilenversionen. `VACUUM` bzw. `autovacuum` gibt ihren Platz frei, sobald keine Transaktion sie mehr braucht.

**F: Was passiert ohne funktionierendes Autovacuum?**
Table Bloat: Die Tabelle wächst, obwohl die Datenmenge gleich bleibt, Queries werden langsamer.

**F: Wie unterscheidet sich das von InnoDB?**
InnoDB legt alte Versionen in ein separates Undo Log (Purge-Thread räumt auf). PostgreSQL lässt sie direkt im Heap.

**F: User oder Group in PostgreSQL?**
Beides heißt **Role**. Mit `LOGIN` verhält sie sich wie ein User, ohne wie eine Gruppe. Rechte vererbt man per `GRANT rolle TO andere_rolle`.

**F: Was ist das WAL?**
Write-Ahead Log: Jede Änderung wird zuerst dort protokolliert, bevor sie als committed gilt. Grundlage für Crash-Recovery, Replikation und PITR.

**F: Asynchrone vs. synchrone Replikation?**
Asynchron (Standard): Primary wartet nicht auf die Replica — schnell, aber beim Absturz können die letzten Commits verloren gehen. Synchron: Primary wartet auf Bestätigung — kein Datenverlust, aber mehr Latenz und Verfügbarkeitsrisiko, wenn die Replica fehlt.

**F: Braucht PostgreSQL Patroni?**
Nein. Die meisten Installationen laufen standalone. Patroni ist ein Orchestrator von außen für HA; PostgreSQL weiß nichts von ihm.

---

## B. Installation, Verbindung, Authentifizierung

**F: Warum zeigt `systemctl status postgresql` „active (exited)"?**
Das ist bei Ubuntu nur ein Meta-Service. Der echte Prozess läuft als `postgresql@16-main`.

**F: Warum klappt `sudo -i -u postgres psql` ohne Passwort?**
Unix-Socket-Verbindung mit **peer**-Authentifizierung: Linux-User `postgres` = Rolle `postgres`.

**F: Was bewirkt `-h localhost` bei `psql`?**
Erzwingt TCP statt Unix-Socket. Dann greift die `host`-Regel in `pg_hba.conf` mit `scram-sha-256` → Passwort nötig.

**F: Woran erkennt man im Prompt, ob man Superuser ist?**
`=#` = Superuser, `=>` = normale Rolle.

**F: Wie wird `pg_hba.conf` ausgewertet?**
Von oben nach unten, die erste passende Zeile gewinnt. Format: `TYPE DATABASE USER ADDRESS METHOD`.

**F: Was regelt `pg_hba.conf`, was `listen_addresses`?**
`pg_hba.conf`: *wer* darf sich verbinden. `listen_addresses`: *wo* der Server überhaupt lauscht. Ohne passendes `listen_addresses` kommen externe Anfragen gar nicht an.

**F: Bestes Werkzeug, um zu sehen, worauf ein Dienst lauscht?**
`sudo ss -tlnp` — Prozess, IP und Port auf einen Blick.

---

## C. Streaming-Replikation & manueller Failover

**F: Welche Rolle darf den WAL-Stream abonnieren?**
Eine mit `REPLICATION`-Attribut (oder Superuser), unabhängig von Tabellenrechten.

**F: Was macht `pg_basebackup -R`?**
Schreibt `standby.signal` und die Verbindungsdaten zum Primary → die Kopie startet als Replica.

**F: Typische Debian-Falle bei `pg_basebackup`?**
Die Config-Dateien liegen unter `/etc`, nicht im Data Directory, und werden daher nicht mitkopiert.

**F: Wie prüft man programmatisch, ob eine Instanz Replica ist?**
`SELECT pg_is_in_recovery();` → `t` = Replica, `f` = Primary.

**F: Was passiert bei einem `INSERT` auf einer Replica?**
`ERROR: cannot execute INSERT in a read-only transaction`. Replicas spielen nur WAL nach.

**F: Die vier Schritte eines manuellen Failovers?**
1. Feststellen, dass der Primary wirklich tot ist. 2. Replica befördern (`pg_ctl promote`). 3. Anwendung umbiegen. 4. Alten Primary sauber aufräumen, nicht einfach wieder als Primary starten.

**F: Was ist Split-Brain?**
Zwei gleichzeitig aktive Primaries, die unabhängig Schreibzugriffe annehmen — z. B. wenn bei einem reinen Netzwerkproblem befördert wird. Kann zu unreparierbaren Datenwidersprüchen führen.

---

## D. Konsens & etcd

**F: Warum darf nicht jeder Knoten selbst über einen Failover entscheiden?**
Bei Netzwerkproblemen haben Knoten unterschiedliche Sichten → Split-Brain.

**F: Wie löst Raft das?**
Eine Entscheidung gilt nur mit **Mehrheit (Quorum)**. Ein isolierter Einzelknoten darf sich nicht selbst zum Leader machen.

**F: Warum ungerade Knotenzahl?**
Bei gerader Zahl ist ein 50/50-Patt möglich, keine Seite hat Mehrheit, der Cluster friert ein. Bei ungerader Zahl ist ein exaktes Patt unmöglich.

**F: Welche Ports nutzt etcd wofür?**
`2380` Peer-Kanal (Knoten untereinander), `2379` Client-Kanal (z. B. Patroni).

**F: Listen vs. Advertise?**
Listen: auf welchen lokalen Adressen ich Verbindungen annehme (darf `127.0.0.1` enthalten). Advertise: welche Adresse ich anderen mitteile — muss im Netz erreichbar sein.

**F: Was muss auf allen drei Knoten identisch sein?**
`ETCD_INITIAL_CLUSTER` (das gemeinsame Adressbuch), `ETCD_INITIAL_CLUSTER_STATE` und `ETCD_INITIAL_CLUSTER_TOKEN`.

**F: `INITIAL_CLUSTER_STATE` „new" vs. „existing"?**
`new`: Cluster wird gemeinsam gegründet. `existing`: neuer Knoten tritt einem laufenden Cluster bei.

**F: Wozu der Cluster-Token?**
Verhindert, dass sich mehrere etcd-Cluster im selben Netz versehentlich vermischen.

**F: Wie prüft man den etcd-Cluster?**
`etcdctl member list` und `etcdctl endpoint health --cluster`.

---

## E. Patroni

**F: Wo läuft Patroni?**
Als eigener Python-Agent auf jedem Knoten neben PostgreSQL. 3 Knoten = 3× PostgreSQL + 3× Patroni.

**F: Wie funktioniert die Leader-Election?**
Der Leader hält in etcd einen Leader-Lock mit TTL und erneuert ihn laufend. Bleibt der Herzschlag aus, läuft der Lock ab, die anderen konkurrieren, dank Raft gewinnt genau einer und befördert sich.

**F: Was passiert beim allerersten Start der drei Patronis?**
Alle versuchen, sich als Initiator einzutragen. Der Gewinner führt `initdb` aus und wird Leader, die anderen holen sich per `pg_basebackup` eine Kopie und werden Replicas.

**F: Wozu die REST-API auf Port 8008?**
Beantwortet „bist du Primary oder Replica?" — `/primary` liefert 200 bzw. 503. Wird von HAProxy genutzt; liefert unter `/metrics` auch Prometheus-Metriken.

**F: Warum `Requires=etcd.service` und `User=postgres` in der systemd-Unit?**
etcd muss laufen, bevor Patroni startet. PostgreSQL-Binaries dürfen nicht als root laufen.

**F: Wo lebt die Cluster-Konfiguration bei Patroni?**
In etcd. Die `bootstrap.dcs`-Sektion der `patroni.yml` wird nur beim allerersten Start gelesen. Danach ändert man Parameter mit `patronictl edit-config`.

**F: Warum nicht `ALTER SYSTEM` oder `postgresql.conf` editieren?**
Patroni überschreibt das wieder. Der Dirigent muss die Kontrolle behalten.

**F: Reload- vs. Restart-Parameter?**
Die meisten greifen per Reload im laufenden Betrieb (z. B. `archive_command`). Fundamentale brauchen einen Neustart (z. B. `archive_mode`) — Patroni zeigt `Pending restart`.

**F: Wie startet man PostgreSQL in einem Patroni-Cluster neu?**
`patronictl restart`, niemals `systemctl restart postgresql` — sonst hält Patroni das für einen Ausfall und reagiert selbst, bis hin zum ungewollten Failover.

**F: Gilt das Superuser-Passwort aus der `patroni.yml` dauerhaft?**
Es wird beim Bootstrap gesetzt. Später geänderte Passwörter (`ALTER ROLE`) stehen nicht automatisch in der Datei — die Datei ist dann nicht mehr die Wahrheit.

**F: Warum ist ein Passwortwechsel der Replikationsrolle tückisch?**
PostgreSQL prüft das Passwort nur beim Verbindungsaufbau. Nach `ALTER ROLE` läuft alles scheinbar weiter — der Fehler zeigt sich erst beim nächsten Reconnect, im schlimmsten Fall während eines Failovers.

**F: Richtige Reihenfolge bei der Passwort-Rotation?**
`ALTER ROLE` → neue Zugangsdaten in der Config aller Knoten → `patronictl reload` → je eine Replica gezielt per `pg_terminate_backend()` trennen und prüfen, ob sie sich neu verbindet.

**F: Auf welchem Knoten zeigt `pg_stat_replication` etwas?**
Nur auf dem Leader (eine Zeile pro Replica, `state = streaming`).

**F: Was verrät `backend_start` in `pg_stat_replication`?**
Wann sich die jeweilige Replica (neu) verbunden hat — nach Failovers sieht man daran den Zeitpunkt des Wechsels.

---

## F. HAProxy, keepalived & VIP

**F: Woher weiß HAProxy, wer Primary ist?**
Es fragt bei allen Knoten Patronis `/primary` auf Port 8008 ab und leitet nur zu dem, der 200 liefert.

**F: Warum `mode tcp`?**
PostgreSQL spricht kein HTTP. Nur der Health-Check läuft über HTTP.

**F: Warum ist die HAProxy-Config auf allen Knoten identisch?**
Sie verweist nur auf feste IPs, nicht auf „sich selbst".

**F: Was zeigt Port 7000?**
Das HAProxy-Stats-Dashboard: welcher Backend-Server gerade UP ist.

**F: Welches Problem löst keepalived?**
HAProxy läuft auf allen drei Knoten — die Anwendung braucht trotzdem *eine* feste Adresse. keepalived gibt per VRRP die VIP an genau einen lebenden Knoten.

**F: Warum hat ein positives `weight` (z. B. 20) den Failover verhindert?**
Bei erfolgreichem Check wird die Priorität erhöht (150 → 170), bei Fehlschlag nur der Bonus wieder abgezogen (→ 150). 150 lag immer noch über node2 (100) und node3 (90), node1 blieb MASTER trotz totem HAProxy. Fix: `weight` weglassen — dann geht die Instanz bei Fehlschlag in den FAULT-Zustand.

**F: Wozu `enable_script_security`, und was ging dabei schief?**
Track-Scripts laufen unter einem unprivilegierten User, standardmäßig `keepalived_script`. Den gab es nicht → keepalived entfernte das Track-Script still, der Health-Check war tot, ohne sichtbaren Fehler. Fix: System-User anlegen. Danach durfte er das Skript wegen `chmod 700` nicht ausführen → Fix: `chmod 755`.

**F: Welchen Hostnamen hat die VIP 192.168.178.200?**
Keinen eigenen. Sie hängt zusätzlich am Interface des Knotens, der gerade MASTER ist.

**F: Warum zeigt die Fritzbox für die .200 „ph-node1"?**
Gleiche MAC-Adresse wie node1 → für die Fritzbox ein Gerät mit zwei IPs.

**F: Warum lande ich per SSH auf .200 auf einem Linux?**
Man landet auf dem aktuellen VIP-Halter; `sshd` lauscht auf allen Adressen. Nach einem VIP-Wechsel meldet SSH `REMOTE HOST IDENTIFICATION HAS CHANGED`.

**F: Wie prüft man, wer die VIP hält?**
`ip -4 addr show | grep 192.168.178.200` auf den Knoten, oder `arp -a` vom Mac (gleiche MAC wie der Halter).

**F: Was zeigt `arp -a`, wenn man keepalived auf node1 stoppt?**
Die VIP wandert, bei der .200 steht dann die MAC des neuen Halters.

**F: Wie lange dauerte der VIP-Umzug im Ausfalltest, und warum?**
~3 Sekunden (3 Pings verloren). Der BACKUP wartet auf rund 3 ausbleibende VRRP-Lebenszeichen (`advert_int 1`), übernimmt dann und verkündet die neue Zuordnung per Gratuitous ARP.

**F: Warum sah die Anwendung ~5 s Verzögerung, aber keine Fehlermeldung?**
TCP wiederholt das SYN beim Verbindungsaufbau automatisch mit wachsenden Abständen. Sobald die VIP wieder da ist, klappt die nächste Wiederholung — sie kommt aber etwas nach der Rückkehr der VIP an.

**F: Holt sich node1 die VIP nach seiner Rückkehr zurück?**
Mit Preemption und höherer Basis-Priorität (150) ja — das kostet erneut einige Sekunden. Mit `nopreempt` bleibt sie beim aktuellen Halter.

**F: Ping auf einen Knoten geht, er fehlt aber in `patronictl list` — warum?**
Betriebssystem läuft, Dienst nicht. Im Lab: Patroni-Autostart war auf allen drei Knoten `disabled`. Prüfen mit `systemctl is-enabled etcd patroni haproxy keepalived`.

> Merksatz: Drei echte Rechner, vier Adressen. Die vierte wandert.

---

## G. Backup & Recovery

**F: Warum Backups trotz Replikation?**
Replikation kopiert auch Fehler (`DROP TABLE` landet auf allen Knoten) und schützt nicht vor Ransomware oder RZ-Ausfall. Replikation schützt vor *Ausfall*, Backup vor *Fehlern und Katastrophen*.

**F: Logisch vs. physisch?**
Logisch (`pg_dump`): SQL-„Rezept", portabel, versionsunabhängig. Physisch (`pg_basebackup`): „Foto" der Dateien, schnell, versionsgebunden, Basis für PITR.

**F: Welches Backup für einen Versionswechsel 16 → 18?**
Logisch, weil SQL versionsunabhängig ist (alternativ `pg_upgrade`).

**F: Was bedeutet `pg_dump -F c`?**
Custom-Format: komprimiert, ideal für `pg_restore`.

**F: Die goldene Regel?**
Ein Backup ist kein Backup, bis man es erfolgreich restored hat.

**F: Was ist PITR?**
Base Backup + archiviertes WAL → Rücksprung auf jede beliebige Sekunde nach dem Backup.

**F: Was braucht PITR zwingend?**
Lückenlose WAL-Archivierung (`archive_mode = on`, `archive_command`).

**F: Was bedeuten `%p` und `%f` im `archive_command`?**
`%p` = vollständiger Pfad der WAL-Datei, `%f` = nur der Dateiname.

**F: Warum muss das Archiv-Verzeichnis auf allen Knoten existieren?**
Jeder Knoten kann Leader werden und muss dann archivieren können. (Live erlebt: node2 mit 567 Fehlversuchen.)

**F: Wie prüft man, ob die Archivierung wirklich läuft?**
`pg_stat_archiver`: `archived_count` muss steigen, `failed_count` darf nicht weiter steigen (historischer Zähler).

**F: Was erzwingt `pg_switch_wal()`?**
Das aktuelle WAL-Segment wird abgeschlossen und damit archiviert.

**F: Wozu `recovery.signal`?**
Sagt PostgreSQL beim Start: Recovery-Modus, WAL bis zum Ziel einspielen.

**F: Was macht `recovery_target_action = 'promote'`?**
Nach Erreichen des Zielzeitpunkts wird die Instanz zum normalen Primary.

**F: Warum PITR nie auf einer Patroni-verwalteten Instanz testen?**
Patroni würde die manuell veränderte Instanz sofort „korrigieren". Deshalb isolierte Test-Instanz auf eigenem Port.

---

## H. Performance mit pgbench

**F: Was misst pgbench?**
Transaktionen pro Sekunde (TPS), Latenz und Fehlerquote bei vielen parallelen Clients.

**F: Was bedeutet `-s 10`?**
Scale Factor, ca. 10 × 100.000 = 1 Mio. Konten.

**F: Wo muss man die Test-DB anlegen?**
Auf dem Leader — Replicas sind read-only.

**F: Warum steigen bei mehr Clients TPS *und* Latenz?**
Die CPUs werden besser ausgelastet (mehr Durchsatz), aber jeder Einzelne wartet länger.

**F: Was ist der Sweet Spot / Sättigung?**
Ab einer Client-Zahl steigt die TPS nicht mehr oder sinkt sogar, nur die Latenz explodiert. Dann hilft nur mehr Hardware.

**F: Was bewirkt `-j`?**
Anzahl der pgbench-Threads (Client-Seite). Zu niedrig → der Lastgenerator ist der Engpass, nicht der Server.

**F: Drei Regeln für saubere Benchmarks?**
Nur eine Variable pro Schritt ändern, Generator nicht zum Engpass werden lassen, Generator getrennt vom Messobjekt betreiben.

**F: Warum war der VIP-Benchmark (1451 TPS) schneller als der direkte?**
Der Leader lag zu dem Zeitpunkt auf einem anderen Knoten als pgbench → getrennte CPUs. In HA-Umgebungen immer den Leader-Zustand mitprotokollieren.

---

## I. Query-Analyse mit EXPLAIN

**F: EXPLAIN vs. EXPLAIN ANALYZE?**
EXPLAIN zeigt nur den geplanten Plan mit Schätzungen. EXPLAIN ANALYZE führt die Query wirklich aus und zeigt echte Zeiten und Zeilen.

**F: Welche Falle hat EXPLAIN ANALYZE bei `DELETE`/`UPDATE`?**
Die Änderung passiert wirklich. Schutz: `BEGIN; EXPLAIN ANALYZE ...; ROLLBACK;`

**F: Wie liest man einen Plan?**
Von innen nach außen. `cost`/`rows` = Schätzung, `actual time`/`rows` = Realität.

**F: Wann wählt der Planner Seq Scan statt Index Scan?**
Wenn ein großer Teil der Tabelle betroffen ist (Faustregel ab etwa 5–10 %). Sequenzielles Lesen schlägt dann viele Einzelsprünge (Straße ablaufen statt Haus für Haus anfahren).

**F: Bedeuten mehr Indizes immer mehr Performance?**
Nein. Jeder Index kostet bei jedem Schreibvorgang und Speicher, und wird bei geringer Selektivität ohnehin nicht genutzt.

**F: Was bedeuten `Parallel Seq Scan` und `Gather`?**
Mehrere Worker lesen Teile der Tabelle parallel, `Gather` sammelt die Ergebnisse ein.

**F: Geschätzte und tatsächliche Zeilen weichen stark ab — warum?**
Veraltete Statistiken. Abhilfe: `ANALYZE tabelle;` (läuft sonst automatisch über Autovacuum).

**F: Warum nutzt `LIKE 'abc%'` bei Collation `de_DE.UTF-8` den normalen Index nicht?**
Der B-Tree sortiert nach Sprachregeln, nicht byteweise. Für Präfix-Suchen braucht es einen Index mit `text_pattern_ops` (oder C-Collation).

---

## J. Monitoring

**F: Pull oder Push bei Prometheus?**
Pull: Prometheus holt die Metriken selbst von den Exportern ab.

**F: Welche Endpunkte gibt es im Lab?**
node_exporter (9100, Betriebssystem), postgres_exporter (9187, Datenbank), Patroni (8008/metrics, Cluster-Rolle) — je auf allen drei Knoten.

**F: Warum eine eigene Monitoring-VM?**
Monitoring muss einen Knotenausfall überleben, und Messwerkzeug neben Messobjekt verfälscht die Messung (Lehre aus pgbench).

**F: `up` vs. `pg_up`?**
`up` = Exporter erreichbar. `pg_up` = Datenbank tatsächlich erreichbar. Wird PostgreSQL über Patroni gestoppt, bleibt `up` = 1, aber `pg_up` = 0.

**F: Was zeigt ein gutes Cluster-Dashboard?**
Leader-Status, Replikations-Lag, Cache-Hit-Ratio, aktive Verbindungen.

**F: Was bedeutet `curl: Couldn't connect … after 0 ms`?**
Sofortige Ablehnung: Rechner erreichbar, auf dem Port lauscht kein Dienst. Ein Timeout nach Sekunden hieße dagegen: Rechner weg oder Firewall verwirft.

**F: Welches Recht bekommt die Monitoring-Rolle, und wo legt man sie an?**
Mitgliedschaft in `pg_monitor` (Statistiken lesen, keine Daten, keine Schreibrechte). Einmal auf dem Leader, die Replikation verteilt sie.

**F: Wie zeigt man in PostgreSQL 16 Rollen-Mitgliedschaften an?**
`\drg` — `\du` hat seit 16 keine Spalte „Member of" mehr.

**F: Warum ein Passwort mit `\password` statt `ALTER ROLE … PASSWORD` setzen?**
`\password` fragt verdeckt ab und schickt es verschlüsselt — kein Klartext in psql-History und Server-Log.

**F: Warum meldet ein Exporter nach einer Passwort-Rotation manchmal noch `pg_up 1`?**
Er hält seine bestehende Verbindung offen; PostgreSQL prüft das Passwort nur beim Verbindungsaufbau. Der Fehler zeigt sich erst beim nächsten Neustart.

**F: Warum fiel der postgres_exporter auf `127.0.0.1:5432` zurück?**
`DATA_SOURCE_NAME` war unlesbar (Tippfehler, fehlendes `host=`). Dort lauscht PostgreSQL im Patroni-Cluster nicht → `connection refused`.

**F: Was prüft `promtool check config`?**
Nur die Syntax der `prometheus.yml`, nicht die Erreichbarkeit der Ziele (die zeigt *Status → Targets*).

**F: Was bewirkt `== 1` in PromQL?**
Filter: Nur Zeitreihen mit Wert 1 bleiben übrig — `patroni_primary == 1` liefert genau den Leader.

**F: Startet Grafana nach `apt install` automatisch?**
Nein, Pakete aus dem Grafana-Repository werden bewusst weder aktiviert noch gestartet: `daemon-reload` + `enable --now grafana-server`.

**F: Warum verbindet sich der Exporter mit der Knoten-IP und nicht mit der VIP?**
Über die VIP würden alle drei Exporter nur den Leader messen, die Replicas wären unsichtbar. Faustregel: Anwendungen über die VIP, Monitoring direkt auf jeden Knoten.

**F: Grafana läuft auf ph-monitor, du öffnest es vom Mac. Warum ist `http://localhost:9090` als Datenquelle richtig?**
Die PromQL-Abfrage stellt der Grafana-Server, nicht der Browser. Aus seiner Sicht ist Prometheus `localhost`. Adressen immer aus der Perspektive dessen lesen, der die Verbindung aufbaut.

**F: gauge oder counter — was ist der Unterschied?**
gauge = aktueller Stand, steigt und fällt (freier RAM, Connections). counter = zählt nur hoch (`node_cpu_seconds_total`); aussagekräftig ist erst die Steigung über `rate()` bzw. `increase()`.

**F: Warum heißen Metriken z. B. `node_memory_MemAvailable_bytes`?**
Prometheus-Konvention: immer Basiseinheiten (Bytes, Sekunden), die Einheit steht im Namen. Umgerechnet wird erst in Grafana.

**F: Prometheus fragt alle 15 s ab. Was bedeutet das für einen Failover?**
Monitoring zeigt Stichproben, keinen Film. Ein Failover erscheint als Sprung; durch gestaffelte Scrapes kann kurz „zwei Leader“ oder „kein Leader“ erscheinen — Messartefakt, kein Split-Brain. Für kurze Ereignisse sind Logs und `patronictl history` die Wahrheit; Alarme bekommen deshalb eine Wartezeit (`for: 1m`).

**F: Wenn du für den Cluster nur drei Alarme einrichten dürftest — welche?** *(typische Interview-Frage)*
1. **Kein oder mehr als ein Leader:** `count(patroni_primary == 1) != 1` für 1 Minute. Null Leader = keine Schreibzugriffe möglich; zwei = Split-Brain-Verdacht.
2. **Datenbank nicht erreichbar:** `pg_up == 0` (bzw. `up == 0` für den Exporter selbst) für 1 Minute — pro Knoten, damit auch eine ausgefallene Replica auffällt, bevor die Redundanz fehlt.
3. **WAL-Archivierung schlägt fehl:** `increase(pg_stat_archiver_failed_count[10m]) > 0`. Ohne Archiv kein PITR — und der Fehler ist im Betrieb völlig unsichtbar (im Lab: 567 Fehlversuche auf node2, die niemand bemerkt hat).
Weitere sinnvolle Kandidaten: Replikations-Lag über Schwellwert, Platte > 85 % voll, letztes Backup älter als 24 h, Verbindungen nahe `max_connections`, etcd ohne Quorum.
Prinzip dahinter: auf **Symptome** alarmieren, die Handeln erfordern — nicht auf jede schwankende Kurve, sonst stumpft das Team ab (Alarm-Müdigkeit).

**F: Wie sieht Monitoring bei 50+ Clustern in einem Unternehmen aus?**
Drei Ebenen: (1) **Alarmierung** über Alertmanager (Mail, Teams, Bereitschaft) — der Mensch wird gerufen, statt Dashboards zu beobachten; (2) **Übersichts-Dashboard** mit einer Zeile pro Cluster in Ampelfarben; (3) **Detail-Dashboards** (wie 1860/9628) als Lupe für die Diagnose. Dazu **Service Discovery** statt handgepflegter IP-Listen (Kubernetes, von Ansible erzeugte Dateien) und **Labels** wie `cluster`, `env`, `team` zum Filtern und Routen der Alarme. Ein Prometheus schafft Tausende Ziele; Thanos/Mimir/VictoriaMetrics erst für mehrere Standorte oder lange Aufbewahrung.

**F: Das PostgreSQL-Dashboard zeigt `shared_buffers = 128 MiB` auf einer 4-GB-VM. Was sagt das?**
Werkseinstellung — der Cluster ist ungetunt. PostgreSQL wird bewusst klein ausgeliefert, damit es überall startet. Üblicher Startwert sind etwa 25 % des RAM.

**F: Was ist `shared_buffers`?**
Der RAM-Bereich, in dem PostgreSQL häufig gebrauchte Tabellenblöcke (Pages à 8 KB) vorhält, damit nicht jedes Mal von der Platte gelesen werden muss. „Shared“, weil sich alle Verbindungen diesen einen Bereich teilen — holt einer eine Tabelle von der Platte, liegt sie danach für alle griffbereit. Bild: Festplatte = Lager im Keller, `shared_buffers` = Werkbank. Werkseinstellung 128 MB, Faustregel ≈ 25 % des RAM (16 GB → 4 GB).

**F: Wie änderst du `shared_buffers` in einem Patroni-Cluster — und reicht ein Reload?** *(typische Interview-Frage)*
„`shared_buffers` lässt sich nicht im laufenden Betrieb ändern, weil PostgreSQL den Speicher beim Start reserviert — ein Reload ist wirkungslos, Patroni zeigt `Pending restart`. Ich setze den Wert mit `patronictl edit-config` (nicht in der `postgresql.conf`, nicht per `ALTER SYSTEM` — das überschreibt Patroni wieder); Patroni verteilt ihn an alle Knoten. Dann starte ich mit `patronictl restart` neu — nicht hart über Proxmox oder `systemctl`.“
Reihenfolge: zuerst den Wert **ändern**, dann **neu starten** — nicht umgekehrt.

**F: Nachfrage: „Und während des Restarts ist unsere Datenbank dann weg?“**
„Nein, wir starten rollierend neu: erst Replica 1, dann Replica 2 — die Anwendung merkt davon nichts, der Leader läuft weiter. Dann übergebe ich per `patronictl switchover` die Leader-Rolle an eine bereits neu gestartete Replica und starte den alten Leader zuletzt. Die Anwendung sieht höchstens beim Switchover eine kurze Unterbrechung von wenigen Sekunden für Schreibzugriffe, bis HAProxy umgeschwenkt hat.“
Die kurze Unterbrechung offen zu nennen wirkt kompetenter als „man merkt gar nichts“.

---

## K. Betrieb & Administration

**F: Wie macht man einen Rolling Reboot?**
`patronictl list` → Replicas einzeln neu starten, warten bis `streaming` → `patronictl switchover` → alten Leader neu starten.

**F: Wie geht man Minor-Updates über viele Datenbanken an?**
Gestaffelt: Testumgebung → weniger kritische Systeme → kritische. Innerhalb eines Clusters rolling (Replicas zuerst, dann Switchover). Minor-Versionen sind binärkompatibel, kein Dump nötig.

**F: Darf man `do-release-upgrade` einfach ausführen?**
Nein: neue PostgreSQL-Hauptversion (eigene Migrationsstrategie) und neues System-Python (betrifft pip-Patroni).

**F: Was ist `tmpfs`?**
Dateisystem im RAM, beim Neustart leer, keine Festplatte. Echte Datenträger: `df -h -x tmpfs`.

**F: Warum hat `/` nur 9,8 GB bei 20-GB-Disk?**
Der Ubuntu-Installer nutzt bei LVM nur etwa die Hälfte. Prüfen mit `sudo vgs` (VFree), erweitern mit `sudo lvextend -r -l +100%FREE /dev/ubuntu-vg/ubuntu-lv`.

**F: Was muss vor dem Klonen eines Templates passieren, was danach?**
Vorher: alles Identische (Pakete), Dienste wie etcd/PostgreSQL stoppen und Daten leeren. Danach pro Knoten: Hostname, IP, `machine-id`, SSH-Host-Keys, knotenspezifische Config.

**F: Warum Full Clone statt Linked Clone?**
Ein Linked Clone hängt dauerhaft am Template — für unabhängige Knoten ungeeignet.

---

## L. Netzwerk & DNS

**F: Was bedeutet `/24`?**
Die ersten 24 Bit sind Netzanteil = `255.255.255.0`. Zwei Schreibweisen derselben Sache.

**F: Warum VirtIO statt E1000?**
Paravirtualisiert: weiß, dass er virtuell läuft, spricht direkt mit dem Hypervisor → schneller, weniger CPU-Last.

**F: Warum müssen Platzhalter wie `<pihole-ip>` inklusive Klammern ersetzt werden?**
`<` und `>` sind für die Shell Umleitungszeichen → `parse error`.

**F: Wo trägt man im Pi-hole v6 einen Namen ein?**
*Settings → Local DNS Records*, nicht *Settings → DNS* (dort stehen die Upstreams).

**F: Warum `pg-vip.home.arpa` statt `pg-vip`?**
`home.arpa` ist für Heimnetze reserviert (RFC 8375). Einteilige Namen bekommen oft eine Suchdomain angehängt und landen bei der Fritzbox.

**F: Wann entsteht eine DNS-Schleife?**
Pi-hole fragt die Fritzbox, die Fritzbox fragt den Pi-hole als Upstream.

**F: Warum überhaupt einen DNS-Namen für die VIP?**
Anwendungen tragen Namen ein; ändert sich die IP, ändert man nur den DNS-Eintrag. Kette: Name → VIP → HAProxy → Leader.

**F: Wird der DNS dadurch zum Single Point of Failure?**
Für Anwendungen ja (neue Verbindungen scheitern mit `could not translate host name`), auch wenn der Cluster per IP erreichbar bleibt. Abhilfe: zwei DNS-Server auf unterschiedlicher Hardware, synchronisierte Einträge, notfalls `/etc/hosts`.

> Merksatz: Hochverfügbarkeit ist nur so stark wie das schwächste Glied der Kette.

---

## M. Einordnung (Bewerbung & Ausblick)

**F: Wie bildet CloudNativePG das Lab ab?**
Der Kubernetes-Operator übernimmt Patronis Rolle, Kubernetes ersetzt etcd als Konsens-Speicher, Services ersetzen HAProxy/VIP, Backups/WAL-Archiv sind deklarativ konfiguriert. Statt Befehle auszuführen beschreibt man den Soll-Zustand in YAML, der Operator gleicht laufend ab (Reconciliation Loop).

**F: Was ist ITIL?**
Ein Prozess-Framework für IT-Betrieb: Incident, Problem, Change Management, SLAs. Rolling Reboots, Postmortems und Runbooks aus dem Lab sind gelebtes ITIL-Denken.
