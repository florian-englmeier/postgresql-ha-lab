# PostgreSQL HA Lab — PostgreSQL + Patroni + etcd + HAProxy + keepalived

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-336791?logo=postgresql&logoColor=white)
![Patroni](https://img.shields.io/badge/Patroni-HA-blue)
![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04_LTS-E95420?logo=ubuntu&logoColor=white)
![Proxmox](https://img.shields.io/badge/Proxmox-VE-E57000?logo=proxmox&logoColor=white)
![etcd](https://img.shields.io/badge/etcd-Raft_Konsensus-419EDA)
![Prometheus](https://img.shields.io/badge/Prometheus-Monitoring-E6522C?logo=prometheus&logoColor=white)
![Grafana](https://img.shields.io/badge/Grafana-Dashboards-F46800?logo=grafana&logoColor=white)
![License](https://img.shields.io/badge/Lizenz-MIT-green)

Ein selbst gebautes, hochverfügbares PostgreSQL-Cluster-Lab auf Proxmox — von den Grundlagen (Architektur, Replikation, manueller Failover) bis zum vollautomatisierten 3-Knoten-Failover mit Patroni, etcd, HAProxy und keepalived — inklusive Backup/PITR, Performance-Analyse und Monitoring mit Prometheus.

Entstanden als strukturiertes Lernprojekt, vollständig dokumentiert als Portfolio-Nachweis.

![Grafana-Dashboard des Clusters: PostgreSQL-Kennzahlen live aus Prometheus](./images/grafana-postgresql-dashboard.png)

*Live-Monitoring des Leaders mit Prometheus und Grafana. Die Kachelreihe „Settings“ zeigt den ersten Befund: `shared_buffers` steht noch auf der Werkseinstellung von 128 MiB.*

---

## Architektur

```
                    ┌─────────────────────┐
                    │  pg-vip.home.arpa    │  ← DNS-Name (Pi-hole)
                    │   Virtuelle IP       │
                    │  192.168.178.200     │  ← keepalived (VRRP)
                    └──────────┬───────────┘
                               │
                    ┌──────────▼───────────┐
                    │       HAProxy         │  ← routet nur zum aktuellen Primary
                    │  (fragt Patroni REST- │     (Health-Check über Port 8008)
                    │   API auf Port 8008)  │
                    └──────────┬───────────┘
                               │
        ┌──────────────────────┼──────────────────────┐
        │                      │                      │
┌───────▼────────┐   ┌─────────▼───────┐   ┌──────────▼──────┐
│   ph-node1      │   │    ph-node2      │   │    ph-node3      │
│ 192.168.178.201 │   │ 192.168.178.202  │   │ 192.168.178.203  │
│                 │   │                  │   │                  │
│  PostgreSQL 16  │   │  PostgreSQL 16   │   │  PostgreSQL 16   │
│  Patroni        │   │  Patroni         │   │  Patroni         │
│  etcd           │   │  etcd            │   │  etcd            │
└─────────────────┘   └──────────────────┘   └──────────────────┘
        └──────────────────── etcd/Raft-Konsensus ─────────────────┘
              (Mehrheitsprinzip entscheidet, wer Primary ist)

┌──────────────────────────────────────────────────────────────────────┐
│ ph-monitor 192.168.178.204 — Prometheus (9090) + Grafana (3000)      │
│ sammelt per Pull: node_exporter :9100 · postgres_exporter :9187 ·    │
│                   Patroni-Metriken :8008 — von allen drei Knoten     │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Live-Nachweis: HAProxy-Routing

![HAProxy Stats-Dashboard: automatisches Routing zur aktuellen Primary](./images/haproxy-stats-dashboard.png)

Das eingebaute HAProxy-Stats-Dashboard (Port `7000`) zeigt live, dass Client-Traffic ausschließlich zur aktuellen Primary (`ph-node1`, grün) geroutet wird — die beiden Replicas werden korrekt aus dem Schreib-Pool ausgeschlossen (rot, weil Patronis REST-API dort `503` statt `200` liefert). Details zur Interpretation im [Tutorial-Dokument](./PostgreSQL_und_Patroni_Tutorial.md#teil-10--haproxy-automatisches-routing-zur-aktuellen-primary).

### Live-Nachweis: Geplanter Switchover

![Geplanter Switchover von ph-node3 auf ph-node2, Timeline 7 auf 8](./images/switchover-timeline-8-history.png)

Rollierendes Patchen aller drei Knoten: Der Leader wird per `patronictl switchover` kontrolliert übergeben, bevor er gepatcht wird. Jeder Wechsel erzeugt eine neue Timeline, `patronictl history` dokumentiert alle Leader-Wechsel lückenlos. Ablauf und Stolpersteine (`needrestart`, Kernel-Drift) in [Teil 17.10](./PostgreSQL_und_Patroni_Tutorial.md#1710-praxis-rollierendes-patchen-des-ganzen-clusters).

### Live-Nachweis: Eigenes HA-Dashboard für den Betrieb

![Eigenes Grafana-Dashboard „PostgreSQL HA-Cluster“: Leader-Status, Replikations-Lag, Cache-Hit-Ratio, Connections, TPS, aktueller Leader](./images/grafana-ha-dashboard.png)

Neben den Community-Dashboards (Dutzende Panels zum Stöbern) ein selbst gebautes Dashboard, das eine Frage beantwortet: **Ist der Cluster gesund — und wenn nicht, wo klemmt es?** Oben links die Ampel für den Bereitschaftsdienst (`sum(patroni_primary)`: `OK` / `KEIN LEADER` / `SPLIT-BRAIN` / `KEINE DATEN`), daneben die Detailkurven für den DBA: Byte-Lag je Replica mit Warnlinie bei einem WAL-Segment (16 MiB), Cache-Hit-Ratio je Knoten mit Schwellen bei 95 / 99 %, Connections mit Warnlinie bei 80 % von `max_connections`. Dazu zwei Sensoren für Lasttest und Failover: Transaktionen pro Sekunde je Knoten und der Name des aktuellen Leaders, der beim Failover sichtbar wechselt. Aufbau, PromQL und Stolpersteine (Standard-Thresholds als „Immer-grün-Ampel“, Lag in Sekunden vs. Bytes, Rohwert vs. Anzeige) in [Teil 17.12](./PostgreSQL_und_Patroni_Tutorial.md#1712-eigenes-ha-dashboard).

---

## Tech-Stack

| Komponente | Version / Rolle |
|---|---|
| **PostgreSQL 16** | Relationale Datenbank |
| **Patroni** | Automatisiert Leader-Election, Failover, Replikationsverwaltung |
| **etcd** | Verteilter Konsensus-Store (Raft), verhindert Split-Brain |
| **HAProxy** | Routet Client-Traffic ausschließlich zum aktuellen Primary |
| **keepalived** | Virtuelle IP (VRRP) als stabiler Einstiegspunkt |
| **Prometheus** | Sammelt Metriken von 11 Zielen (Pull-Prinzip, 15-s-Intervall) |
| **node_exporter / postgres_exporter** | Betriebssystem- und Datenbank-Metriken je Knoten; Exporter mit eigener `pg_monitor`-Rolle |
| **Grafana** | Dashboards: Node Exporter Full (1860), PostgreSQL (9628); eigenes HA-Dashboard `PostgreSQL HA-Cluster` (Leader-Status, aktueller Leader, Lag, Cache-Hit-Ratio, Connections, TPS) |
| **Pi-hole** | Lokaler DNS: `pg-vip.home.arpa` → VIP |
| **Proxmox VE** | Virtualisierungsplattform für die 3 Cluster-Knoten |
| **Ubuntu Server** | 24.04 LTS, je Knoten |

---

## Setup & Reproduzierbarkeit

Wer dieses Lab selbst nachbauen möchte, findet den vollständigen Lernweg — alle Konzepte, Befehle, Konfigurationsdateien und Entscheidungen — im [Tutorial-Dokument](./PostgreSQL_und_Patroni_Tutorial.md). Das Setup ist Schritt für Schritt reproduzierbar.

### Infrastruktur

- 3× Ubuntu Server 24.04 LTS VMs (2 vCPU / 4 GB RAM / 20 GB Disk)
- 1× Monitoring-VM `ph-monitor` (VMID 204, `192.168.178.204`, 2 vCPU / 2 GB / 20 GB) — bewusst getrennt vom Cluster, damit das Monitoring Knotenausfälle überlebt
- Netz: `192.168.178.0/24` (Heimnetz), statische IPs `.201`–`.203`, virtuelle IP `.200`
- Strategie: Template-Knoten (`ph-node1`) vollständig vorbereitet (Pakete installiert, noch keine knotenspezifische Config), dann zweimal geklont — knotenspezifisches Konfigurieren (IP, Hostname, machine-id, SSH-Keys) erst nach dem Klonen

### etcd-Cluster: Peer- vs. Client-Kommunikation

Jeder etcd-Knoten braucht zwei getrennte Adressen:
- **Peer-URL** (Port `2380`): Kommunikation der drei Knoten untereinander (Raft-Konsensus — Leader-Wahl, Log-Replikation)
- **Client-URL** (Port `2379`): Schnittstelle für Patroni ("wer ist aktuell Primary?")

**Listen**-Adressen legen fest, wo ein Knoten selbst lauscht; **Advertise**-Adressen sind die erreichbare Netz-IP, die den anderen Knoten mitgeteilt wird. Die `initial-cluster`-Liste (Name + Peer-URL je Knoten) muss auf allen drei Knoten identisch sein — sie ist das gemeinsame Adressbuch beim Cluster-Start. Volle Erklärung mit Beispiel-Configs im [Tutorial-Dokument](./PostgreSQL_und_Patroni_Tutorial.md).

---

## Fortschritt

### ✅ Abgeschlossen

**Grundlagen & Replikation (Single-VM)**
- [x] PostgreSQL-Architektur: Cluster, PGDATA, Rollen, MVCC/VACUUM, WAL
- [x] Streaming-Replikation von Hand aufgesetzt, Replica read-only verifiziert
- [x] Manueller Failover per `pg_ctl promote`, Split-Brain-Problematik verstanden
- [x] Konsens-Theorie: etcd/Raft, Quorum, warum ungerade Knotenzahl

**HA-Cluster auf Proxmox (3 Knoten)**
- [x] Template-Knoten `ph-node1` vorbereitet, zweimal geklont und individualisiert (Hostname, IP, machine-id, SSH-Keys)
- [x] etcd-3-Knoten-Cluster, Patroni-Cluster (Leader + 2 Replicas, Lag = 0)
- [x] HAProxy mit Health-Check gegen die Patroni-REST-API, routet automatisch zur Primary
- [x] keepalived mit virtueller IP `192.168.178.200` (Unicast-VRRP, Track-Script); drei Bugs beim Aufsetzen gefunden und behoben
- [x] Automatischer Failover-Test Ende-zu-Ende: VIP und Traffic wandern, `psql` über die VIP bleibt erreichbar
- [x] DNS-Name `pg-vip.home.arpa` über Pi-hole: Name → VIP → HAProxy → Leader verifiziert
- [x] Ausfalltest des VIP-Halters gemessen: VIP-Umzug ~3 s, Anwendung ~5 s verzögert ohne Fehler, kein Patroni-Failover

**Backup & Recovery**
- [x] Logisches Backup `pg_dump` / `pg_restore` mit Restore-Test
- [x] Physisches Backup `pg_basebackup`, WAL-Archivierung über `patronictl edit-config`
- [x] Point-in-Time-Recovery sekundengenau auf isolierter Testinstanz bewiesen
- [x] Archiv-Lücke nach Failover per `pg_stat_archiver` gefunden und behoben

**Performance & Query-Analyse**
- [x] `pgbench`-Sättigungskurve (10/50/90 Clients), Durchsatz-Latenz-Trade-off, Lasttest über VIP mit 0 % Fehlern
- [x] Gegenprobe vom getrennten Lastgenerator `ph-monitor`: 2 831 vs. 2 977 TPS (im Rauschen), Laststufen live im eigenen Dashboard; Befund: der VIP-Knoten zahlt die HAProxy-Weiterleitung mit ~10 Punkten CPU
- [x] `EXPLAIN ANALYZE`: Seq Scan vs. Index Scan, Selektivität, Collation-Falle (`de_DE.UTF-8`) mit `text_pattern_ops` gelöst

**Betrieb & Härtung**
- [x] Patroni-Autostart war auf allen Knoten deaktiviert, behoben und per Neustart-Test bestätigt
- [x] `/etc/patroni.yml` (enthält Passwörter) von weltlesbar auf `root:postgres 640`
- [x] Rollierendes Patchen aller drei Knoten mit zwei geplanten Switchovers (Timeline 7 → 8 → 9), Kernel-Drift durch Phased Updates erkannt und behoben, `needrestart`-Falle am Leader dokumentiert
- [x] **Failover unter Last** (pgbench, 50 Clients, Stromausfall des Leaders per `qm stop`): **≈ 35 s ohne Leader** (aus `ttl` 30 s + Wahl, im Patroni-Log gemessen), Ampel live „KEIN LEADER“, kein bestätigter Commit verloren; pgbench-Clients brechen ab — Wiederverbinden ist Aufgabe der Anwendung
- [x] Befund beim Wiederanlauf: Replica blieb nach `pg_rewind` mit fehlendem WAL hängen (Checkpoint mitten im Lasttest, `wal_keep_size` 0, Archiv nur lokal) → `patronictl reinit`; Schutzschicht `wal_keep_size` 1GB eingeführt und mit einem zweiten Ausfall unter Last nachgewiesen (880 MB Lücke, Rückkehr ohne Eingriff)
- [x] **`shared_buffers` 128 MB → 1 GB** per `edit-config`, rollierender Restart (Replicas, dann Switchover); Vorher/Nachher mit Aufwärm-Lauf: Cache-Hit-Ratio Leader 94 % → 99 %, TPS unverändert (CPU ist der Engpass, Fehlgriffe kamen vorher aus dem OS-Page-Cache)
- [x] Incident: Leader-Platte 100 % voll durch lokales WAL-Archiv ohne Aufbewahrung (11 GB nach zwei Tagen Lasttests), etcd auf demselben Knoten beendet sich; gezielt im Archiv aufgeräumt; der etcd-Neustart löste über `Requires=etcd.service` einen Leader-Wechsel aus

**Monitoring**
- [x] Eigene Monitoring-VM `ph-monitor`, getrennt vom Cluster
- [x] node_exporter, Patroni-Metriken, postgres_exporter mit `pg_monitor`-Rolle (inkl. Passwort-Rotation)
- [x] Prometheus mit 11/11 Zielen `UP`
- [x] Grafana mit Prometheus-Datenquelle, Dashboards 1860 (Node Exporter Full) und 9628 (PostgreSQL)
- [x] Befund aus dem Dashboard: `shared_buffers` und weitere Parameter stehen noch auf Werkseinstellung
- [x] Eigenes HA-Dashboard in Grafana: Leader-Status (inkl. Split-Brain-Erkennung), aktueller Leader, Replikations-Lag, Cache-Hit-Ratio, Connections, TPS
- [x] Root-FS bei ~70 %: Inventur (OS, DB, WAL-Archiv, Logs) und `lvextend` auf allen drei Knoten im laufenden Betrieb, 9,8 → 18 GB

**Kernziel erreicht:** vollautomatisierter 3-Knoten-Failover ohne manuellen Eingriff, Ende-zu-Ende verifiziert — inklusive Backup/PITR, Performance-Nachweis, Query-Analyse und Monitoring.

> Details zu den drei Bugs beim Aufsetzen von keepalived (VRRP-`weight`-Logik, `enable_script_security`, Dateiberechtigungen) stehen in [Teil 12 des Tutorials](./PostgreSQL_und_Patroni_Tutorial.md#teil-12--der-echte-failover-test-und-drei-bugs-unterwegs).

### 🔜 Als Nächstes

- [ ] Zentrales WAL-Archiv mit Aufbewahrungsregel (pgBackRest) und `restore_command` — Befund 20.10.2026: lokales Archiv lief auf dem Leader voll
- [ ] Panel „Replicas streaming“ und Alarm auf Plattenfüllstand

---

## Lessons Learned

- **Replikation ersetzt kein Backup.** Replikation schützt vor dem Ausfall eines Knotens, nicht vor einem versehentlichen `DROP TABLE`. Deshalb Base Backup plus WAL-Archivierung für Point-in-Time-Recovery, und ein Backup gilt erst als Backup, wenn der Restore getestet ist. Weil der Leader wandert, muss das WAL-Archiv auf allen drei Knoten funktionieren.
- **Patroni besitzt die PostgreSQL-Konfiguration.** Parameter werden nur über `patronictl edit-config` geändert, nie per `ALTER SYSTEM` oder in der `postgresql.conf`. Entscheidend ist, ob ein Parameter einen Reload oder einen Restart braucht. Restart-Parameter werden rollierend angewendet: erst die Replicas, der Leader per Switchover zuletzt. Den Diff vor dem Bestätigen lesen und danach mit `SHOW` prüfen, denn ein Tippfehler fällt sonst erst beim nächsten Neustart auf.
- **Patchen kann einen Failover auslösen.** `needrestart` startet nach `apt upgrade` automatisch `patroni.service` neu, auf dem Leader ist das ein ungeplanter Failover. Daher rollierendes Patchen mit Switchover vor dem Leader und anschließend Kernel-Versionen vergleichen, weil Phased Updates zu Versionsdrift zwischen den Knoten führen.
- **Benchmarks im HA-Cluster brauchen den Leader-Zustand.** Läuft der Lastgenerator auf dem Leader-Knoten, konkurrieren beide um dieselben CPUs und die Messung kippt. Leader-Position und Parameter werden zu jedem Lauf protokolliert, pro Schritt ändert sich nur eine Variable.
- **Ein Dashboard beantwortet die Frage seiner Zielgruppe.** Der Bereitschaftsdienst braucht in zwei Sekunden eine Ampel, nicht fünfzig Panels. Grafanas Standard-Schwellen (Base grün, 80 rot) hätten „kein Leader“ und „Split-Brain“ grün gefärbt — Thresholds werden deshalb bewusst gesetzt und gegen den Rohwert verglichen, nicht gegen die formatierte Anzeige.
- **Monitoring misst jeden Knoten direkt.** Anwendungen gehen über die VIP, Exporter nicht, sonst wird nur der Leader gemessen. Alarme sitzen auf Symptomen (kein oder zwei Leader, `pg_up == 0`, WAL-Archiv scheitert) und haben eine Wartezeit, weil Scrape-Intervalle kurze Ereignisse verzerren. Für den genauen Ablauf eines Failovers sind `patronictl history` und die Logs maßgeblich.
- **Ein Failover ist erst fertig, wenn die Reserve wieder streamt.** Der Cluster lief nach dem Ausfall grün weiter, während eine Replica wegen einer WAL-Lücke festhing — Ursache ein Checkpoint drei Stunden vorher, mitten im Lasttest. Ausfalltests prüfen deshalb auch den Wiederanlauf und das Monitoring selbst: Zwei Panels zeigten „Geister“ (letzter Wert eines toten Knotens), eines war per gespeicherter Legenden-Auswahl blind. Lösung: Instant-Queries für „Wer ist jetzt …?“, `wal_keep_size` als Reserve, zentrales WAL-Archiv als nächster Schritt.
- **Tuning trifft nur, wenn es den Engpass trifft.** `shared_buffers` hob die Cache-Hit-Ratio von 94 auf 99 %, der Durchsatz blieb gleich: Die Fehlgriffe kamen aus dem RAM des Betriebssystems, und die CPU war am Anschlag. Vorher-Messung, Aufwärm-Lauf und nur eine geänderte Variable machen den Vergleich erst aussagekräftig.
- **Ein offener Punkt im Betriebslog ist eine Zeitbombe.** „Archiv ohne Aufbewahrungsregel“ war notiert — einen Tag später stand der Leader mit voller Platte da, und etcd auf demselben Datenträger fiel mit.

---

## Roadmap

Dieses Lab ist ein lebendes Projekt — der Cluster steht, die Grundlagen sind dokumentiert. Geplante Erweiterungen:

| # | Thema | Beschreibung |
|---|---|---|
| 1 | **Alerting** | Alertmanager-Regeln (Leader weg, Lag zu hoch, Archivierung fehlgeschlagen) statt Dashboards beobachten |
| 2 | **Connection Pooling** | PgBouncer vor HAProxy schalten — reduziert Verbindungs-Overhead bei vielen Clients |
| 3 | **Sicherheitshärtung** | 🔧 begonnen (Dateirechte `patroni.yml`, Exporter-Config) — offen: `keepalived.conf`, SSL/TLS, `pg_hba.conf` Restriktionen, BSI IT-Grundschutz |
| 4 | **Automatisierung mit Ansible** | Cluster-Aufbau als Ansible-Rolle — reproduzierbar statt Schritt-für-Schritt von Hand |
| 5 | **Read-only Load Balancing** | Replicas über separaten HAProxy-Port (z.B. `5433`) für Leseabfragen nutzen |
| 6 | **Switchover vs. Failover** | `patronictl switchover` (kontrolliert) vs. automatischer Failover — Unterschied live demonstrieren |
| 7 | **pg_upgrade** | Versionswechsel (z.B. PostgreSQL 16 → 17) im laufenden Cluster dokumentieren |
| 8 | **CloudNativePG** | PostgreSQL-HA auf Kubernetes (on-prem) als Gegenstück zum Patroni-Ansatz |
| 9 | **Failure Domains** | Alle drei Knoten teilen sich einen Proxmox-Host und eine Platte (Befund 19.10.2026: ~50 % `iowait` auf einer Replica unter Last). Ausbau: PostgreSQL-Knoten auf separater x86-Hardware (i7), per Skript in den laufenden Cluster aufgenommen. Für echten automatischen Failover über Hardware-Grenzen müssen die **etcd-Stimmen** auf drei Geräte verteilt werden (Proxmox, i7, Raspberry Pi als Schiedsrichter) — kein Gerät darf allein die Mehrheit halten |

---

## Dokumentation

Der vollständige Lernweg inkl. aller Konzepte, Befehle und Entscheidungen steht im [Tutorial-Dokument](./PostgreSQL_und_Patroni_Tutorial.md).

Jede Änderung am laufenden Cluster steht mit Grund und Ergebnis im [Betriebslog](./Betriebslog.md).

Architektur inspiriert von [technotim.live — PostgreSQL High Availability](https://technotim.live/posts/postgresql-high-availability/), eigenständig auf Proxmox umgesetzt und dokumentiert.

---

## Autor

Erstellt von **Florian Englmeier** als praktisches Portfolio-Projekt im Rahmen der Weiterqualifizierung zum PostgreSQL-Datenbankadministrator.

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Florian_Englmeier-0077B5?logo=linkedin&logoColor=white)](https://linkedin.com/in/florian-englmeier-620949102)
[![GitHub](https://img.shields.io/badge/GitHub-bavarian--dataforge-181717?logo=github&logoColor=white)](https://github.com/florian-englmeier)

---

## Lizenz

MIT — siehe [LICENSE](./LICENSE).
