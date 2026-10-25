#!/usr/bin/env bash
# cluster-check.sh – Hausmeister-Rundgang über alle Patroni-Knoten
# Stufe 1: Plattenplatz des Root-Dateisystems je Knoten anzeigen.
# Läuft am besten auf ph-monitor (SSH-Key zu allen Knoten nötig).

SSH_USER="florian"
KNOTEN=(192.168.178.201 192.168.178.202 192.168.178.203)

for ip in "${KNOTEN[@]}"; do
  echo "== $ip =="
  ssh -o BatchMode=yes -o ConnectTimeout=3 "$SSH_USER@$ip" 'df -h /'
done
