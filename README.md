# PostgreSQL HA Lab — PostgreSQL + Patroni + etcd + HAProxy + keepalived

Ein selbst gebautes, hochverfügbares PostgreSQL-Cluster-Lab auf Proxmox — von den Grundlagen (Architektur, Replikation, manueller Failover) bis zum vollautomatisierten 3-Knoten-Failover mit Patroni, etcd, HAProxy und keepalived.

Entstanden als strukturiertes Lernprojekt (interaktives Tutoring), dokumentiert für das eigene Portfolio.

## Architektur

```
                    ┌─────────────────────┐
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
```

## Tech-Stack

| Komponente | Rolle |
|---|---|
| **PostgreSQL 16** | Relationale Datenbank |
| **Patroni** | Automatisiert Leader-Election, Failover, Replikationsverwaltung |
| **etcd** | Verteilter Konsensus-Store (Raft), verhindert Split-Brain |
| **HAProxy** | Routet Client-Traffic ausschließlich zum aktuellen Primary |
| **keepalived** | Virtuelle IP (VRRP) als stabiler Einstiegspunkt |
| **Proxmox VE** | Virtualisierungsplattform für die 3 Cluster-Knoten |

## Setup

- 3× Ubuntu Server 24.04 LTS VMs (2 vCPU / 4 GB RAM / 20 GB Disk)
- Netz: `192.168.178.0/24` (Heimnetz), statische IPs `.201`–`.203`, virtuelle IP `.200`
- Ein Template-Knoten (`ph-node1`) vollständig vorbereitet (Pakete installiert, noch keine knotenspezifische Config), dann zweimal geklont — Details siehe [Tutorial-Dokument](./PostgreSQL_und_Patroni_Tutorial.md)

## Fortschritt

- [x] PostgreSQL-Grundlagen (Architektur, Rollen, MVCC/VACUUM, WAL)
- [x] Streaming-Replikation (manuell, Single-VM-Testumgebung)
- [x] Manueller Failover live durchgeführt & verstanden (Split-Brain-Problematik)
- [x] Konsensus-Theorie: etcd/Raft, Mehrheitsprinzip
- [x] Patroni-Konzept: Automatisierung des manuellen Failover-Prozesses
- [x] HAProxy- und keepalived-Konzept
- [x] `ph-node1` (VMID 201) in Proxmox provisioniert, PostgreSQL 16 + Patroni + etcd installiert
- [ ] `ph-node2` / `ph-node3` per Klon erstellt und individualisiert (Hostname, IP, machine-id, SSH-Keys)
- [ ] etcd-3-Knoten-Cluster konfiguriert
- [ ] Patroni-Cluster konfiguriert und gestartet
- [ ] HAProxy konfiguriert
- [ ] keepalived konfiguriert
- [ ] Kompletter automatisierter Failover-Test durchgeführt

## Dokumentation

Der vollständige Lernweg inkl. aller Konzepte, Befehle und Entscheidungen steht im [Tutorial-Dokument](./PostgreSQL_und_Patroni_Tutorial.md).

Referenz: [technotim.live — PostgreSQL High Availability](https://technotim.live/posts/postgresql-high-availability/)

## Lizenz

MIT — siehe [LICENSE](./LICENSE).
