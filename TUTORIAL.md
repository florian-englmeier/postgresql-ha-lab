# PostgreSQL & Patroni — Lern-Tutorial

Persönliches Tutorial/Lernprotokoll, entstanden aus einem interaktiven Tutoring-Track. Ziel: PostgreSQL und Patroni (High Availability) strukturiert verstehen — erst PostgreSQL als eigenständiges System, danach HA/Patroni als zusätzliche Schicht.

Stand: 26.08.2026

---

## Teil 0 — PostgreSQL-Architektur-Grundlagen

### Der "Cluster"

In PostgreSQL nennt man das, was auf einem einzelnen Server läuft, wenn man PostgreSQL installiert und startet, einen **Cluster**. Wichtig: Das hat zunächst nichts mit mehreren Servern oder Hochverfügbarkeit zu tun (das kommt erst später bei Patroni dazu) — hier ist "Cluster" einfach eine einzelne laufende PostgreSQL-Instanz auf einer Maschine.

Ein Cluster kann **mehrere Datenbanken gleichzeitig** enthalten. Direkt nach der Installation gibt es meist schon Standard-Datenbanken: `postgres`, `template0`, `template1`. Eigene Datenbanken kommen dazu.

Besonderheit: Eine einzelne Verbindung zu Postgres ist immer nur mit **genau einer** Datenbank gleichzeitig verbunden. Man kann nicht einfach "umschalten" — dafür braucht man eine neue Verbindung (oder Spezial-Erweiterungen wie `dblink`). Die Datenbanken innerhalb eines Clusters sind stark voneinander isoliert.

### Das Data Directory (PGDATA)

Alle Datenbanken eines Clusters liegen physisch in **einem einzigen Ordner** — dem Data Directory, oft `PGDATA` genannt (z.B. `/var/lib/postgresql/16/main`).

Wichtige Inhalte:

| Pfad | Inhalt |
|---|---|
| `base/` | Die eigentlichen Tabellen-/Index-Dateien, ein Unterordner pro Datenbank |
| `pg_wal/` | Die WAL-Segmente (Write-Ahead Log) — zentral für Crash-Recovery und Replikation |
| `postgresql.conf` | Zentrale Server-Konfiguration (Speicherlimits, Logging, Netzwerk, etc.) |
| `pg_hba.conf` | "Türsteher"-Datei: legt fest, welcher Client (IP, User, Auth-Methode) sich verbinden darf |
| `postmaster.pid` | Zeigt an, dass und mit welcher Prozess-ID der Server läuft |

### MVCC (Multi-Version Concurrency Control)

PostgreSQL hat — anders als z.B. MySQL mit austauschbaren Storage-Engines (MyISAM/InnoDB) — genau **eine feste Engine**, die nach dem MVCC-Prinzip arbeitet.

Kernidee: Ein `UPDATE` überschreibt eine Zeile **nicht** an Ort und Stelle. Stattdessen wird eine komplett **neue Version** der Zeile geschrieben, und die alte Version wird nur als "veraltet" markiert (nicht sofort gelöscht). Ein `DELETE` funktioniert ähnlich. So blockieren lesende und schreibende Transaktionen sich gegenseitig nicht — jede Transaktion sieht einfach die für sie passende Version.

Diese veralteten Zeilenversionen heißen **"dead tuples"**. Es gibt kein festes Limit, wie viele davon entstehen können — das hängt z.B. davon ab, wie lange andere Transaktionen noch laufen.

### VACUUM

Damit die Tabelle nicht unbegrenzt wächst, gibt es den Hintergrundprozess **`VACUUM`** (automatisch als `autovacuum`). Er entfernt tote Tupel physisch, sobald sie wirklich niemand mehr braucht, und gibt den Platz zur Wiederverwendung frei. Ohne funktionierendes Autovacuum bläht sich eine Tabelle auf ("Table Bloat") — sie wird größer, obwohl die Datenmenge gleich bleibt, und Queries werden langsamer.

*(Vergleich zu MySQL/InnoDB: InnoDB macht intern auch MVCC, legt alte Versionen aber in einem separaten "Undo Log" ab, das von einem "Purge"-Thread aufgeräumt wird — statt wie Postgres direkt im Haupt-Tabellenspeicher ("Heap").)*

### Rollen & Berechtigungen

PostgreSQL kennt kein getrenntes Konzept von "User" und "Group" — beides heißt **"Role"**.

- Eine Rolle mit dem Attribut `LOGIN` kann sich verbinden (verhält sich wie ein "User").
- Eine Rolle ohne `LOGIN` kann sich nicht verbinden, dient nur als Container für Rechte (verhält sich wie eine "Group").
- Rollen können anderen Rollen zugewiesen werden: `GRANT rolle_name TO andere_rolle` — das vererbt Rechte (Gruppen-Pattern). Typisches Muster: ein paar Gruppen-Rollen mit klar definierten Rechten (z.B. nur Lesen) + einzelne Login-Rollen, die man in die passende Gruppe steckt statt jedes Recht einzeln zu vergeben.

### WAL & Replikation — Grundprinzip

Jede Änderung wird zuerst ins **WAL** (Write-Ahead Log) geschrieben, bevor sie als "committed" bestätigt wird. Bei **Streaming-Replikation** wird dieser WAL-Strom an eine oder mehrere Replicas geschickt, die ihn nachspielen.

Wichtiger Trade-off — **asynchrone vs. synchrone Replikation**:

- **Asynchron (Standard):** Der Primary wartet beim `COMMIT` *nicht* darauf, dass die Replica die Änderung empfangen hat. Schnell, aber: Stürzt der Primary genau in diesem Moment ab, sind die letzten committeten Änderungen, die die Replica noch nicht erreicht haben, **verloren** — sie liegen nur auf der toten Primary-Platte.
- **Synchron** (`synchronous_commit` + `synchronous_standby_names`): Der Primary wartet auf Bestätigung der Replica, bevor er dem Client "committed" meldet. Kein Datenverlust im Failover-Fall, aber höhere Latenz und ein Verfügbarkeitsrisiko, falls die Replica mal nicht erreichbar ist.

*(Dieses Thema wird in einer späteren Lektion noch vertieft, sobald Streaming-Replikation praktisch aufgesetzt wird.)*

### Wichtig: PostgreSQL funktioniert auch komplett ohne Patroni

Die überwiegende Mehrheit aller PostgreSQL-Installationen läuft als einzelne, eigenständige Instanz ohne jede Replikation oder HA-Tooling. **Patroni** kommt erst ins Spiel, wenn man mehrere PostgreSQL-Instanzen zu einem hochverfügbaren Verbund mit automatischem Failover zusammenschalten will. Patroni speichert selbst keine Daten — es ist ein Orchestrator "von außen", der mehrere eigenständige PostgreSQL-Cluster überwacht und im Ernstfall einen Failover durchführt. PostgreSQL selbst "weiß" nichts von Patroni.

→ Deshalb: Erst PostgreSQL solo verstehen und einsetzen können, Patroni kommt danach als zusätzliche Schicht.

---

## Teil 1 — Hands-on: PostgreSQL Installation

### Umgebung

- Parallels-VM auf Mac (Apple Silicon / ARM), unabhängig vom Proxmox-Homelab
- Ubuntu 24.04.4 LTS ("noble"), Hostname `ubuntu-gnu-linux-24-04-3`
- Linux-User: `parallels`

### Installation

```bash
sudo apt update
sudo apt install -y postgresql postgresql-contrib
```

- `postgresql` — Kernpaket (Server + Client-Tools)
- `postgresql-contrib` — nützliche Zusatz-Erweiterungen

Ergebnis: PostgreSQL **16.15** (Ubuntu-Paket, aarch64-Build) installiert, keine Fehler. Cluster `16/main` wurde automatisch angelegt unter `/var/lib/postgresql/16/main` (= das PGDATA-Verzeichnis aus Teil 0). Der Installer legt außerdem automatisch einen Linux-Systembenutzer `postgres` (Besitzer der Dateien) sowie eine gleichnamige PostgreSQL-Superuser-Rolle `postgres` an.

### Dienst prüfen

```bash
sudo systemctl status postgresql
```

Hinweis: `postgresql.service` ist bei Ubuntu nur ein **Meta-Service**, der prüft, ob alle installierten Cluster-Versionen laufen, und sich dann selbst beendet (`active (exited)` ist normal!). Der eigentliche Serverprozess läuft unter einem versionierten Service, z.B. `postgresql@16-main`.

### Erste Verbindung (als Superuser)

```bash
sudo -i -u postgres psql
```

Im `psql`-Prompt getestet:

```sql
SELECT version();
```

→ Bestätigt: `PostgreSQL 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1) on aarch64-unknown-linux-gnu`.

### Eigene Rolle + Datenbank anlegen (Praxis zu Teil 0)

Statt dauerhaft als Superuser `postgres` zu arbeiten, wurde eine eigene Login-Rolle plus Datenbank angelegt:

```sql
CREATE ROLE flo WITH LOGIN PASSWORD 'ein_test_passwort';
CREATE DATABASE testdb OWNER flo;
```

### Verbindung als neue Rolle — peer vs. host Authentifizierung

```bash
psql -h localhost -U flo -d testdb
```

Wichtiges Detail: Ohne `-h localhost` würde die Verbindung über den lokalen Unix-Socket laufen, und dort gilt standardmäßig **"peer"-Authentifizierung** — der Linux-Login-Name muss exakt mit dem Postgres-Rollennamen übereinstimmen (deshalb funktionierte `sudo -i -u postgres psql` ohne Passwort). Mit `-h localhost` wird eine TCP-Verbindung erzwungen, für die eine andere Regel in `pg_hba.conf` greift — dort wird ein Passwort verlangt (scram-sha-256), passend zum vorher gesetzten Passwort für `flo`.

Erkennungsmerkmal im Prompt: `testdb=>` (statt `testdb=#`) zeigt an, dass man **kein** Superuser mehr ist.

---

## Teil 2 — Rollen-Rechte in der Praxis & pg_hba.conf

### Rechte-Grenzen live getestet

Als nicht-Superuser-Rolle `flo` in `testdb` ausprobiert:

```sql
CREATE TABLE notizen (id SERIAL PRIMARY KEY, text TEXT);
```
→ **Funktioniert** — `flo` ist Besitzer von `testdb`, darf also Tabellen anlegen.

```sql
CREATE ROLE noch_ein_user WITH LOGIN;
```
→ **Permission denied** — `CREATE ROLE` ist ein Superuser-Recht (bzw. braucht das `CREATEROLE`-Attribut), das `flo` nicht hat. Bestätigt live, dass die Rollen-Rechte aus Teil 0 tatsächlich greifen.

### pg_hba.conf im Detail

Wichtiger Hinweis zur Ubuntu/Debian-Paketierung: `postgresql.conf` und `pg_hba.conf` liegen bei Debian-basierten Systemen **nicht** im Data Directory, sondern unter `/etc/postgresql/16/main/` (Debian-Konvention: Konfiguration unter `/etc`). Die eigentlichen Daten bleiben unter `/var/lib/postgresql/16/main`.

Angeschaut mit:
```bash
sudo grep -v '^#' /etc/postgresql/16/main/pg_hba.conf | grep -v '^$'
```

Format jeder Zeile: `TYPE  DATABASE  USER  ADDRESS  METHOD`. Regeln werden von oben nach unten geprüft, **erste passende Zeile gewinnt**.

Inhalt (Standard-Konfiguration nach Installation):

```
local   all             postgres                                peer
local   all             all                                     peer
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             ::1/128                 scram-sha-256
local   replication     all                                     peer
host    replication     all             127.0.0.1/32            scram-sha-256
host    replication     all             ::1/128                 scram-sha-256
```

Erklärung der wichtigsten Zeilen:
- `local all postgres peer` — warum `sudo -i -u postgres psql` ohne Passwort funktioniert (Linux-User `postgres` == Rolle `postgres`).
- `local all all peer` — warum eine lokale Verbindung als `flo` (ohne `-h localhost`) NICHT funktioniert hätte: kein Linux-User `flo` vorhanden.
- `host all all 127.0.0.1/32 scram-sha-256` — warum `psql -h localhost -U flo -d testdb` nach einem Passwort fragt (TCP-Verbindung → diese Regel statt peer).
- Die `replication`-Zeilen sind Sonderregeln für die Pseudo-Datenbank `replication`, die für WAL-Streaming zwischen Primary und Replica gebraucht wird — aktuell nur von localhost erlaubt.

**Für eine echte Replica auf einer zweiten Maschine später nötig:**
1. Neue Zeile in `pg_hba.conf` mit der IP/dem Subnetz der Replica, z.B. `host replication replicator_user 192.168.178.0/24 scram-sha-256` (neue Zeile hinzufügen, bestehende nicht überschreiben).
2. Zusätzlich `listen_addresses` in `postgresql.conf` anpassen (Standard: nur `localhost`) — `pg_hba.conf` regelt *wer* darf, `listen_addresses` regelt *wo der Server überhaupt lauscht*. Ohne Anpassung von `listen_addresses` kommen externe Verbindungsversuche gar nicht erst an.

## Teil 3 — Streaming-Replikation live aufgesetzt

Für den ersten praktischen Replikations-Versuch wurde **auf derselben VM** ein zweiter PostgreSQL-Prozess auf einem anderen Port als Replica eingerichtet (statt gleich einer zweiten Maschine) — zeigt den vollen Mechanismus ohne zusätzliche Netzwerk-Komplexität. Eine echte zweite Maschine kommt später für den vollen Patroni-Aufbau.

### 1. Replikations-Rolle auf dem Primary

```sql
CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'replica_pass_123';
```

Das `REPLICATION`-Attribut ist unabhängig von normalen Tabellenrechten — nur Rollen damit (oder Superuser) dürfen den WAL-Stream abonnieren.

### 2. Basis-Backup ziehen

```bash
sudo -u postgres pg_basebackup -h 127.0.0.1 -p 5432 -U replicator -D /var/lib/postgresql/16/replica -P -R
```

- `-D` — Zielverzeichnis, wird das neue PGDATA der Replica
- `-R` — schreibt automatisch `standby.signal` + Verbindungsdaten zum Primary (Postgres 12+)
- Die bestehende `pg_hba.conf`-Regel `host replication all 127.0.0.1/32 scram-sha-256` erlaubte das sofort, keine Änderung nötig (nur lokal).

**Stolperfalle (Debian-spezifisch):** `pg_basebackup` kopiert nur, was tatsächlich im Data Directory liegt. Da Debian/Ubuntu `pg_hba.conf`/`postgresql.conf` nach `/etc/postgresql/16/main/` auslagert (siehe Teil 2), fehlten beide Dateien in der Kopie komplett → Start schlug fehl (`could not load .../replica/pg_hba.conf`). Fix: Dateien manuell in den Replica-Datenordner kopieren, da eine manuell gestartete Instanz (ohne Debian-Cluster-Tooling) sie dort standardmäßig sucht:

```bash
sudo cp /etc/postgresql/16/main/pg_hba.conf /var/lib/postgresql/16/replica/pg_hba.conf
sudo chown postgres:postgres /var/lib/postgresql/16/replica/pg_hba.conf
```

### 3. Port setzen & Replica starten

```bash
echo "port = 5433" | sudo tee -a /var/lib/postgresql/16/replica/postgresql.conf
sudo -u postgres /usr/lib/postgresql/16/bin/pg_ctl -D /var/lib/postgresql/16/replica -l /var/lib/postgresql/16/replica/logfile start
```

→ `server started`. Manuell mit `pg_ctl` statt über den Debian-Service, da dieser zweite Cluster nicht in dessen Verwaltung registriert ist.

### 4. Verifiziert

```sql
-- auf dem Primary:
SELECT client_addr, state, sync_state FROM pg_stat_replication;
-- → 127.0.0.1 | streaming | async

-- auf der Replica (Port 5433):
SELECT pg_is_in_recovery();
-- → t
```

`pg_is_in_recovery()` ist die Funktion, mit der eine Anwendung (oder später Patroni/HAProxy) programmatisch prüfen kann, ob eine Instanz Primary oder Replica ist.

### 5. Live-Test: Schreiben auf Primary, Lesen auf Replica

```bash
psql -h 127.0.0.1 -p 5432 -U flo -d testdb -c "INSERT INTO notizen (text) VALUES ('Hallo von Primary');"
psql -h 127.0.0.1 -p 5433 -U flo -d testdb -c "SELECT * FROM notizen;"
```
→ Die Zeile "Hallo von Primary" erscheint auf der Replica, obwohl sie nur auf dem Primary eingefügt wurde. Replikation bestätigt Ende-zu-Ende.

*(Nebenbei gelernt: Ein `!` in einem doppelt gequoteten Bash-`-c`-String löst History-Expansion aus (`bash: !': event not found`) und lässt den Befehl gar nicht erst laufen — reine Shell-Falle, nichts mit Postgres zu tun.)*

### 6. Replica ist read-only

```bash
psql -h 127.0.0.1 -p 5433 -U flo -d testdb -c "INSERT INTO notizen (text) VALUES ('Test von Replica');"
```
→ `ERROR: cannot execute INSERT in a read-only transaction`. Bestätigt: Eine Streaming-Replica nimmt niemals eigene Schreibbefehle an, sie spielt ausschließlich den WAL vom Primary nach.

## Teil 4 — Manueller Failover live durchgeführt

### Warum HA nötig ist

Ein einzelner PostgreSQL-Server ist ein Single Point of Failure — Hardwaredefekt, OS-Crash, geplante Wartung, menschlicher Fehler. Fällt er aus, ist die Anwendung tot, bis jemand manuell eingreift.

### Was "manuell eingreifen" konkret bedeutet

1. Feststellen, dass der Primary wirklich tot ist (nicht nur kurz nicht erreichbar)
2. Die Replica befördern ("promote")
3. Die Anwendung auf die neue Primary umbiegen
4. Den alten Primary später sauber aufräumen (darf nicht einfach als Primary wieder starten — Datenstand könnte abweichen)

Jeder Schritt kostet Zeit — genau die Downtime, die HA/Patroni auf Sekunden reduzieren soll.

### Split-Brain-Gefahr

Wird eine Replica befördert, während der alte Primary in Wirklichkeit noch läuft (z.B. nur Netzwerkproblem statt echtem Absturz), entstehen **zwei gleichzeitig aktive Primaries**, die unabhängig voneinander Schreibzugriffe annehmen — **Split-Brain**, potenziell nicht mehr reparierbarer Datenwiderspruch. Genau dieses Problem macht einen zuverlässigen Konsens-Mechanismus (etcd/Raft) für automatisierte Failover-Systeme nötig.

### Live durchgeführt

```bash
# Primary "abstürzen lassen"
sudo systemctl stop postgresql@16-main

# Bestätigt: App wäre jetzt tot
psql -h 127.0.0.1 -p 5432 -U flo -d testdb -c "SELECT 1;"
# → Connection refused

# Replica (Port 5433) zur neuen Primary befördern
sudo -u postgres /usr/lib/postgresql/16/bin/pg_ctl -D /var/lib/postgresql/16/replica promote
# → server promoted

# Bestätigt: kein Standby mehr
psql -h 127.0.0.1 -p 5433 -U flo -d testdb -c "SELECT pg_is_in_recovery();"
# → f

# Bestätigt: nimmt jetzt Schreibzugriffe an
psql -h 127.0.0.1 -p 5433 -U flo -d testdb -c "INSERT INTO notizen (text) VALUES ('Ich bin jetzt Primary');"
# → INSERT 0 1
```

Kompletter manueller Failover erfolgreich durchgeführt und verifiziert. Offen (bewusst nicht gemacht): alten Primary (5432) sauber als neue Replica der jetzigen Primary (5433) wieder einrichten.

## Teil 5 — Konsensus-Problem & etcd/Raft

### Das Problem

Bei mehreren PostgreSQL-Knoten (z.B. 3, orchestriert von Patroni) muss im Ausfallfall irgendjemand zuverlässig entscheiden: "Der alte Primary ist wirklich tot, wir befördern jetzt eine Replica." Dürfte jeder Knoten das für sich selbst entscheiden, landet man sofort wieder beim Split-Brain-Problem (siehe Teil 4) — besonders bei Netzwerkproblemen, bei denen unterschiedliche Knoten unterschiedliche Sichten auf die Lage haben.

### Die Lösung: Mehrheits-Konsensus (Raft)

**Raft** (implementiert von **etcd**) löst das über ein Mehrheitsprinzip: Eine Entscheidung gilt nur dann als gültig, wenn eine **Mehrheit (Quorum)** aller Knoten zustimmt — nie nur ein einzelner Knoten für sich.

Beispiel bei 3 Knoten: Ein Netzwerkproblem teilt den Cluster in eine Gruppe von 2 und einen isolierten Einzelknoten. Die Gruppe von 2 hat die Mehrheit (2 von 3) und darf handeln (z.B. neuen Leader wählen). Der isolierte Knoten weiß: keine Mehrheit → darf sich NICHT selbst zum Leader machen, auch wenn er den Rest nicht mehr sieht. Split-Brain wird so zuverlässig verhindert.

### Warum ungerade Knotenzahl (3, 5, 7 statt 2, 4, 6)

Bei einer geraden Anzahl (z.B. 4) kann sich der Cluster exakt 50/50 aufteilen (2 vs. 2) — keine Seite hat die nötige Mehrheit (bräuchte 3 von 4). Ergebnis: Der Cluster "friert ein", niemand wählt einen neuen Leader, bis die Verbindung wiederhergestellt ist. Lieber kurzzeitig keine Verfügbarkeit als zwei widersprüchliche Leader gleichzeitig. Bei ungerader Knotenzahl ist ein exaktes Patt rechnerisch unmöglich.

### Rolle von etcd für Patroni

Patroni erfindet dieses Konsensus-Problem nicht neu, sondern nutzt etcd als fertiges, battle-tested System dafür. Patroni selbst führt keine eigene Wahl durch — es schreibt/liest lediglich einen Eintrag in etcd (z.B. "wer ist aktuell der Primary"), und etcd sorgt intern über Raft dafür, dass sich alle Knoten auf genau einen konsistenten Stand einigen.

## Teil 6 — Was Patroni konkret macht

Patroni ist ein eigenständiger (Python-)Agent-Prozess, der auf **jedem** Knoten neben der jeweiligen PostgreSQL-Instanz läuft (nicht in Postgres eingebaut). Auf einem 3-Knoten-Cluster laufen also 3× PostgreSQL + 3× Patroni.

Was Patroni automatisiert — direkt gespiegelt an den manuellen Schritten aus Teil 4:

1. **Verwaltet den lokalen PostgreSQL-Prozess** (start/stop/konfigurieren) — automatisiert das, was wir von Hand mit `pg_ctl` gemacht haben.
2. **Leader-Election über etcd**: Der Patroni-Prozess auf dem aktuellen Primary hält in etcd einen "Leader Lock" mit Ablaufzeit (TTL), den er laufend erneuert (Herzschlag). Bleibt der Herzschlag aus, läuft der Lock ab.
3. **Automatischer Failover**: Sobald der Lock frei wird, konkurrieren die übrigen Patroni-Prozesse darum — dank etcd/Raft-Mehrheitsprinzip kann garantiert nur einer gewinnen. Der Gewinner befördert seine lokale Instanz automatisch (der `pg_ctl promote`-Schritt von vorhin, jetzt automatisiert).
4. **REST-API** (Standard-Port 8008) je Knoten: Beantwortet "bist du gerade Primary oder Replica?". Wird von HAProxy für Health-Checks genutzt.
5. Versucht in der Regel auch, einen wiederkehrenden alten Primary automatisch als neue Replica einzugliedern (Detail für später, klappt nicht immer ohne manuellen Eingriff).

### Die verbleibende Lücke: Anwendung umbiegen

Patroni weiß intern, wer Primary ist — aber die Anwendung selbst nicht automatisch. Genau das übernimmt **HAProxy**: Es sitzt als stabiler Eintrittspunkt vor allen Knoten, fragt laufend über Patronis REST-API ab, wer gerade Primary ist, und leitet Verbindungen ausschließlich dorthin. Die Anwendung verbindet sich immer mit derselben HAProxy-Adresse und merkt vom Failover im Hintergrund nichts.

## Offene nächste Schritte

- HAProxy (Health-Checks, Routing zum Primary)
- keepalived / Virtual IP (VRRP)
- Referenz-Gesamtarchitektur: [technotim.live PostgreSQL-HA-Anleitung](https://technotim.live/posts/postgresql-high-availability/) (3-Knoten-Cluster: PostgreSQL + etcd + Patroni + HAProxy + keepalived)

---

## Teil 7 — Capstone-Projekt: Echter 3-Knoten-Cluster auf Proxmox

Ab hier verlassen wir die Single-VM-Testumgebung (Parallels) und bauen den Cluster real auf drei Proxmox-VMs nach. Projekt-Repo: [github.com/florian-englmeier/postgresql-ha-lab](https://github.com/florian-englmeier/postgresql-ha-lab) (MIT-Lizenz).

### Strategie: Ein Template klonen statt dreimal von Hand installieren

Statt drei VMs komplett einzeln aufzusetzen: eine VM (`ph-node1`) vollständig mit allen Paketen vorbereiten, dann zweimal klonen. Wichtige Regel dabei: Alles, was auf allen Knoten **identisch** sein muss (Pakete), kommt vor dem Klonen rein. Alles, was pro Knoten **eindeutig** sein muss (Hostname, IP, `machine-id`, SSH-Host-Keys, spätere Patroni-/etcd-Config), wird bewusst **nach** dem Klonen, pro Knoten einzeln, konfiguriert — sonst kollidieren die Klone im Netzwerk.

### Netzwerk- und Sizing-Schema

Heimnetz `192.168.178.0/24` (Fritzbox-DHCP bis `.254`), IPs vorab per Ping + Fritzbox-Geräteliste als frei verifiziert:

| Knoten | VMID | Hostname | IP |
|---|---|---|---|
| Node 1 | 201 | ph-node1 | 192.168.178.201 |
| Node 2 | 202 | ph-node2 | 192.168.178.202 |
| Node 3 | 203 | ph-node3 | 192.168.178.203 |
| Virtuelle IP (später, HAProxy/keepalived) | — | — | 192.168.178.200 |

Sizing pro Knoten: 2 vCPU / 4 GB RAM / 20 GB Disk (für dieses Lernprojekt ausreichend — PostgreSQL, Patroni und etcd sind im Leerlauf alle drei genügsam; erst bei Lasttests oder großen Datenmengen würde man hier nachlegen).

OS: **Ubuntu Server 24.04 LTS**, volle Server-Version (nicht "minimized" — mehr Debug-Komfort für's Tutorial), OpenSSH-Server bei Installation aktiviert, keine Featured Snaps installiert (bewusst alles klassisch über `apt`/`pip` statt Snap, für konsistente, dokumentierbare Config-Pfade).

Proxmox-VM-Netzwerk: Bridge `vmbr0`, Modell **VirtIO (paravirtualized)** — treiberbasierter virtueller Adapter, der (im Gegensatz zu einem emulierten Adapter wie Intel E1000) weiß, dass er virtualisiert läuft, und direkter mit dem Hypervisor kommuniziert: spürbar schneller, weniger CPU-Overhead. Ubuntu 24.04 bringt die nötigen VirtIO-Treiber von Haus aus mit.

Statische IP wurde direkt im Ubuntu-Installer gesetzt (Subiquity, manueller IPv4-Modus) statt per DHCP + Fritzbox-Reservierung — einfacher, weil die Netplan-Config (`/etc/netplan/00-installer-config.yaml`) beim Klonen sowieso pro Knoten angepasst werden muss.

*Kleiner Exkurs Subnetzmaske:* `/24` (CIDR) und `255.255.255.0` (klassische Maske) sind zwei Schreibweisen für **dieselbe** Sache — `/24` heißt "die ersten 24 Bit der Adresse sind der Netzwerk-Anteil" (binär: `11111111.11111111.11111111.00000000`), umgerechnet exakt `255.255.255.0`. Man kombiniert nie beide Schreibweisen gleichzeitig.

### Paket-Installation auf dem Template (ph-node1)

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y postgresql postgresql-contrib python3-pip python3-psycopg2 etcd-server etcd-client
sudo pip install patroni[etcd] --break-system-packages
```

Ergebnis: PostgreSQL 16.15, Patroni 4.1.5, etcdctl 3.4.30.

Zwei Dinge zu dieser Zeile, die leicht zu verwechseln sind:

- **`patroni[etcd]`** — pip-"Extras"-Syntax: installiert Patroni-Kern **plus** die passende Python-Client-Bibliothek für den gewählten Consensus-Store (Patroni unterstützt neben etcd auch Consul, ZooKeeper u.a.).
- **`--break-system-packages`** — kein Paket, sondern eine reine `pip`-Kommandozeilen-Option, die Ubuntu 24.04s PEP-668-Schutz (`externally-managed-environment`) bewusst übersteuert. Der Schutz verhindert normalerweise, dass `pip` versehentlich das von `apt` verwaltete System-Python durcheinanderbringt. Für eine dedizierte Single-Purpose-VM (läuft nur Patroni) ist das Risiko vernachlässigbar.

`etcd` kommt bewusst über `apt`, nicht `pip` — es ist ein in Go geschriebenes, fertig kompiliertes Binary, kein Python-Paket.

### Cleanup vor dem Klonen

Sowohl `etcd` als auch `postgresql` starten nach der Installation automatisch mit einer Default-Einzelknoten-Konfiguration — das würde beim Klonen mitkopiert und später Probleme machen (analog zum `machine-id`-Problem, nur auf Anwendungsebene):

```bash
# etcd hat sich bereits selbst zum Einzelknoten-Cluster-Leader gewählt und Daten
# unter /var/lib/etcd abgelegt — den richtigen 3-Knoten-Cluster bauen wir erst,
# wenn alle IPs feststehen (nächster Schritt)
sudo systemctl stop etcd
sudo systemctl disable etcd
sudo rm -rf /var/lib/etcd/*

# PostgreSQL-Autostart deaktivieren — Patroni übernimmt die Prozess-Steuerung
# später komplett selbst, der systemd-Autostart würde dem in die Quere kommen
sudo systemctl stop postgresql
sudo systemctl disable postgresql
```

### Geplante Post-Klon-Schritte (pro Klon einzeln, über die Proxmox-Konsole — nicht SSH, da die Klone anfangs dieselbe IP wie das Template haben und SSH bei IP-Konflikt unzuverlässig ist)

- Hostname ändern (`ph-node2` / `ph-node3`)
- Netplan-IP ändern (`/etc/netplan/00-installer-config.yaml`, dann `sudo netplan apply` — sofortige Übernahme ohne Reboot)
- `machine-id` neu generieren
- SSH-Host-Keys neu generieren

### Status

`ph-node1` fertig installiert und für den Klon vorbereitet. Als Nächstes: `ph-node1` sauber herunterfahren, in Proxmox zweimal als Full Clone (nicht Linked Clone) auf VMID 202/203 kopieren.

### Exkurs: Git — "fetch first" beim ersten Push ins GitHub-Repo

Beim Verbinden des lokalen Projektordners mit dem auf GitHub.com bereits angelegten Repo trat folgender Fehler auf:

```
! [rejected]        main -> main (fetch first)
error: failed to push some refs to 'https://github.com/florian-englmeier/postgresql-ha-lab.git'
```

**Ursache:** Beim Anlegen des Repos über die GitHub-Weboberfläche hatte GitHub automatisch schon einen ersten Commit im `main`-Branch erzeugt (typisch, wenn beim Erstellen z.B. "Add a README file" oder eine Lizenzvorlage angehakt ist). Lokal wurde das Verzeichnis dagegen mit `git init` als **komplett neues, unabhängiges Repo** gestartet — eine eigene Commit-Historie ganz ohne Bezug zum GitHub-Commit.

Git erlaubt einen `push` standardmäßig nur als **Fast-Forward**: Der aktuelle Stand des Remote-Branches muss ein direkter Vorfahre dessen sein, was hochgeladen wird. Da hier zwei völlig getrennte Wurzel-Commits aufeinandertrafen, hätte ein einfacher Push den GitHub-Commit stillschweigend überschrieben — das verhindert Git bewusst mit dieser Fehlermeldung.

**Lösung:**

```bash
git fetch origin
git merge origin/main --allow-unrelated-histories -X ours -m "merge: lokale README/LICENSE behalten"
git push -u origin main
```

- `--allow-unrelated-histories` — erlaubt das Zusammenführen zweier Repos ohne gemeinsamen Ursprungs-Commit (Git verweigert das sonst standardmäßig als Sicherheitsmaßnahme).
- `-X ours` — bei echten Datei-Konflikten (z.B. beide Seiten haben eine `README.md`) gewinnt automatisch die lokale Version, ohne manuelle Konfliktauflösung.

Ergebnis: ein Merge-Commit mit **zwei Elternteilen** (lokaler Wurzel-Commit + GitHub-Wurzel-Commit), der beide Historien zusammenführt. Sichtbar mit:

```bash
git log --oneline --graph --all --decorate
```

Danach war der lokale `main`-Branch ein echter Fast-Forward-Nachfolger des Remote-Standes, der Push ging durch.

## Teil 8 — etcd als 3-Knoten-Cluster konfigurieren

Bisher lief etcd auf jedem Knoten isoliert für sich (deaktiviert und mit leerem Datenverzeichnis seit dem Klon-Cleanup). Jetzt bringen wir den drei Knoten bei, sich gegenseitig zu finden und gemeinsam den Raft-Cluster zu bilden, den wir konzeptionell schon aus Teil 5 kennen.

### Zwei getrennte Kommunikationskanäle

Man kann sich die drei etcd-Prozesse als ein dreiköpfiges Gremium vorstellen, das per Raft gemeinsam Entscheidungen trifft. Dieses Gremium braucht zwei unterschiedliche Kanäle:

- **Peer-Kanal, Port `2380`** — die private Leitung zwischen den Knoten selbst: Abstimmen, Protokolle abgleichen, Leader wählen.
- **Client-Kanal, Port `2379`** — der öffentliche Schalter, an dem Außenstehende (später: Patroni) Fragen stellen ("wer ist gerade Primary?").

Deshalb gibt es in der Config-Datei für jeden Kanal ein eigenes Adress-Paar.

### "Listen" vs. "Advertise" — der typische Stolperstein

- **Listen** beantwortet: "An welchen Türen meines eigenen Hauses nehme ich Besuch an?" — rein lokal, auf der Maschine selbst (inkl. `127.0.0.1` für lokalen Zugriff).
- **Advertise** beantwortet: "Welche Adresse gebe ich anderen, damit sie mich von außen finden?" — muss eine im Netz erreichbare, echte IP sein. `127.0.0.1` wäre hier nutzlos, weil das für einen anderen Knoten "ich selbst" bedeuten würde, nicht "der andere Knoten".

Jeder Knoten lauscht auf seiner eigenen Adresse (Listen) UND ruft gleichzeitig aktiv die Advertise-Adressen der beiden anderen an — das läuft in beide Richtungen parallel, keine Einbahnstraße.

### Das gemeinsame Adressbuch: `ETCD_INITIAL_CLUSTER`

Diese Zeile muss auf **allen drei Knoten identisch** sein — sie ist das gemeinsame Adressbuch: "hier sind Namen und Adressen aller drei Gründungsmitglieder". Ohne dieses Adressbuch wüsste keiner der drei, wen er überhaupt kontaktieren soll.

Zwei weitere Einstellungen dazu:

- **`ETCD_INITIAL_CLUSTER_STATE="new"`** — sagt den dreien: "Wir gründen hier gerade gemeinsam einen brandneuen Cluster." (Im Unterschied zu `"existing"`, das man nutzen würde, um einem bereits laufenden Cluster später einen vierten Knoten hinzuzufügen.)
- **`ETCD_INITIAL_CLUSTER_TOKEN`** — ein eindeutiger Name für genau diesen einen Cluster. Rein theoretisch könnten im selben Netzwerk mehrere unabhängige etcd-Cluster existieren — der Token verhindert, dass die sich versehentlich vermischen, falls sich z. B. IP-Bereiche überschneiden würden.

### Die Config-Dateien

`/etc/default/etcd` auf jedem Knoten (Debian/Ubuntu-Paket liest diese Environment-Datei beim Start des systemd-Dienstes ein). Gleicher Aufbau auf allen drei Knoten, nur `ETCD_NAME` und die eigene IP in den vier "eigenen" Zeilen ändern sich — `ETCD_INITIAL_CLUSTER`, `_STATE` und `_TOKEN` bleiben überall identisch:

```bash
# ph-node1 (192.168.178.201)
sudo tee /etc/default/etcd > /dev/null <<'CFG'
ETCD_NAME="ph-node1"
ETCD_DATA_DIR="/var/lib/etcd/default.etcd"
ETCD_INITIAL_CLUSTER="ph-node1=http://192.168.178.201:2380,ph-node2=http://192.168.178.202:2380,ph-node3=http://192.168.178.203:2380"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_INITIAL_CLUSTER_TOKEN="ph-etcd-cluster-1"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://192.168.178.201:2380"
ETCD_LISTEN_PEER_URLS="http://192.168.178.201:2380,http://127.0.0.1:2380"
ETCD_LISTEN_CLIENT_URLS="http://192.168.178.201:2379,http://127.0.0.1:2379"
ETCD_ADVERTISE_CLIENT_URLS="http://192.168.178.201:2379"
CFG
```

Auf `ph-node2` und `ph-node3` derselbe Block mit `ETCD_NAME`, `ETCD_INITIAL_ADVERTISE_PEER_URLS`, `ETCD_LISTEN_PEER_URLS`, `ETCD_LISTEN_CLIENT_URLS` und `ETCD_ADVERTISE_CLIENT_URLS` auf die jeweils eigene IP (`.202` bzw. `.203`) angepasst.

Aktivieren und starten (Reihenfolge egal — etcd wartet von selbst, bis es die anderen erreicht):

```bash
sudo systemctl enable etcd
sudo systemctl start etcd
```

Cluster-Gesundheit prüfen (auf einem beliebigen Knoten):

```bash
etcdctl member list
etcdctl endpoint health --cluster
```

**Ergebnis (verifiziert am 16.09.2026):** Alle drei Knoten haben sich gefunden, jeder mit eigener Member-ID im Status `started`, und der Health-Check bestätigt für alle drei Endpoints ein erfolgreich committetes Proposal — das Mehrheitsprinzip funktioniert nicht nur theoretisch, sondern live:

![etcd 3-Knoten-Cluster: member list und Health-Check](./images/etcd-cluster-health.png)

## Teil 9 — Patroni konfigurieren und Cluster starten

Datenverzeichnis (`/var/lib/postgresql/16/patroni`, `postgres:postgres`, `chmod 700`) und `patroni.yml` auf jedem Knoten angelegt (Details siehe Config-Auszug oben in der Session-Historie — `scope`, `restapi`, `etcd3` und `postgresql`-Block jeweils mit der eigenen IP, Replikations-/Superuser-Passwort auf allen drei Knoten identisch).

### systemd-Unit

`pip install` legt keinen systemd-Dienst an — selbst geschrieben, identisch auf allen drei Knoten unter `/etc/systemd/system/patroni.service`:

```ini
[Unit]
Description=Patroni PostgreSQL HA
After=network.target etcd.service
Requires=etcd.service

[Service]
Type=simple
User=postgres
Group=postgres
ExecStart=/usr/local/bin/patroni /etc/patroni.yml
ExecReload=/bin/kill -s HUP $MAINPID
KillMode=process
TimeoutSec=30
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

`User=postgres`, weil Patroni die PostgreSQL-Binaries startet und die aus Sicherheitsgründen nicht als root laufen dürfen. `Requires=etcd.service` stellt sicher, dass der lokale etcd-Dienst garantiert läuft, bevor Patroni startet.

### Was beim ersten Start automatisch passiert

Alle drei Patroni-Prozesse versuchen beim Start gleichzeitig, sich in etcd als Initiator einzutragen — dank Raft/Mehrheitsprinzip gewinnt genau einer. Der Gewinner führt `initdb` aus und wird automatisch **Leader**. Die anderen beiden erkennen über etcd, dass bereits ein Leader existiert, und ziehen sich automatisch per `pg_basebackup` eine Kopie davon — werden also automatisch zu **Replicas**. Das ist exakt der Automatisierungsschritt aus Teil 6, jetzt live beobachtet statt nur konzeptionell.

```bash
sudo systemctl daemon-reload
sudo systemctl enable patroni
sudo systemctl start patroni
```

### Verifiziert (17.09.2026)

```
florian@ph-node2:~$ patronictl -c /etc/patroni.yml list
+ Cluster: postgres-ha (7686474206101860353) ------+----+-------------+-----+------------+-----+
| Member   | Host            | Role    | State     | TL | Receive LSN | Lag | Replay LSN | Lag |
+----------+-----------------+---------+-----------+----+-------------+-----+------------+-----+
| ph-node1 | 192.168.178.201 | Leader  | running   |  1 |             |     |            |     |
| ph-node2 | 192.168.178.202 | Replica | streaming |  1 |   0/5047D30 |   0 |  0/5047D30 |   0 |
| ph-node3 | 192.168.178.203 | Replica | streaming |  1 |   0/5047D30 |   0 |  0/5047D30 |   0 |
+----------+-----------------+---------+-----------+----+-------------+-----+------------+-----+
```

`ph-node1` hat das Rennen gewonnen und ist Leader, `ph-node2`/`ph-node3` sind Replicas im Zustand `streaming` mit **Lag = 0** in beiden Spalten (Receive und Replay LSN) — vollständig synchron, alle auf derselben Timeline (`TL 1`).

## Teil 10 — HAProxy: automatisches Routing zur aktuellen Primary

HAProxy soll nie selbst "wissen" müssen, wer gerade Primary ist — das würde die Config ständig veralten lassen. Stattdessen nutzt es Patronis REST-API (Port 8008): Der Pfad `/primary` antwortet mit HTTP **200**, wenn der jeweilige Knoten gerade Primary ist, und mit **503**, wenn er Replica ist. HAProxy fragt das laufend bei allen drei Knoten ab und leitet echten PostgreSQL-Traffic (Port 5432) ausschließlich an den einen Knoten weiter, der gerade mit 200 antwortet. Fällt der Primary aus und Patroni befördert automatisch eine Replica, schwenkt HAProxy automatisch um — ganz ohne manuellen Eingriff.

Praktischer Vorteil dieser Konfiguration: Sie ist auf **allen drei Knoten identisch** (zeigt ja nur auf feste IPs, nicht auf "sich selbst") — keine Anpassung pro Knoten nötig, anders als bei etcd und Patroni.

```bash
sudo apt install -y haproxy

sudo tee /etc/haproxy/haproxy.cfg > /dev/null <<'CFG'
global
    maxconn 100

defaults
    log global
    mode tcp
    retries 2
    timeout client 30m
    timeout connect 4s
    timeout server 30m
    timeout check 5s

listen stats
    mode http
    bind *:7000
    stats enable
    stats uri /

listen postgres
    bind *:5000
    option httpchk GET /primary
    http-check expect status 200
    default-server inter 3s fall 3 rise 2 on-marked-down shutdown-sessions
    server ph-node1 192.168.178.201:5432 maxconn 100 check port 8008
    server ph-node2 192.168.178.202:5432 maxconn 100 check port 8008
    server ph-node3 192.168.178.203:5432 maxconn 100 check port 8008
CFG

sudo systemctl enable haproxy
sudo systemctl restart haproxy
```

`mode tcp` bei der `postgres`-Regel, weil PostgreSQL kein HTTP spricht — nur der Health-Check gegen Patroni läuft über HTTP, der eigentliche Datenverkehr ist rohes TCP. `listen stats` auf Port 7000 ist ein eingebautes Web-Dashboard (`http://<knoten-ip>:7000/`), auf dem live sichtbar ist, welcher Server gerade "UP" ist.

### Verifiziert (17.09.2026)

`psql` lokal auf dem Mac installiert (`brew install libpq`), dann über HAProxy verbunden:

```
psql -h 192.168.178.201 -p 5000 -U postgres -c "SELECT pg_is_in_recovery();"
 pg_is_in_recovery
--------------------
 f
(1 row)
```

`f` (false) bestätigt: Die Verbindung über HAProxy (Port 5000) landet tatsächlich bei der aktuellen Primary — Routing funktioniert wie gedacht.
