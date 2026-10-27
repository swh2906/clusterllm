# ClusterLLM — Bedienungs- und Konfigurationsdoku

Verteilte LLM-Inferenz mit **llama.cpp über RPC**. Die Control Plane lädt das Modell und verteilt die Layer über das Cluster-Netz auf die GPUs der Worker und auf ihre eigene GPU.

## 1. Aufbau

```
                 Cluster-Netz 10.10.10.0/24 (eigenes Ethernet-Segment, ohne Gateway)
 ┌──────────────────────────┐
 │ Control Plane 10.10.10.5 │──── RPC :50052 ──▶ node-01  10.10.10.6  ggml-rpc-server (RPC0)
 │ llama-server :8080 (API) │──── RPC :50052 ──▶ node-02  10.10.10.7  ggml-rpc-server (RPC1)
 │ lokale GPU (CUDA0)       │──── RPC :50052 ──▶ node-03  10.10.10.8  ggml-rpc-server (RPC2)
 └──────────────────────────┘
```

| Komponente | Version / Wert |
|---|---|
| Betriebssystem | Ubuntu 22.04.5 LTS (Server) |
| GPU | Turing, Compute Capability 7.5, 4 GB VRAM pro Node |
| NVIDIA-Treiber | `nvidia-driver-580` (auf allen Nodes identisch) |
| CUDA-Toolkit | 11.5 aus den Ubuntu-Paketquellen (`nvidia-cuda-toolkit`) |
| Host-Compiler | GCC 10 (nvcc 11.5 unterstützt kein GCC > 11) |
| llama.cpp | Commit `daef7b6874397a5a7c3d7e38b55e2ee0adf7da38`, gebaut mit CUDA + RPC |
| Modell | `unsloth/gemma-4-12B-it-qat-GGUF:UD-Q4_K_XL` (48 Layer) |
| Verteilung | `--split-mode layer`, `--tensor-split 1,1,1,1` |
| Admin-User | `aiadmin` |

## 2. Dateien im Repo

| Datei | Zweck |
|---|---|
| `cluster.conf` | **Einzige Konfigurationsdatei.** Auf allen Nodes identisch halten |
| `lib.sh` | Gemeinsame Funktionen (wird von den Skripten geladen) |
| `01_system_setup.sh` | Treiber, CUDA, GCC 10, Build- und Monitoring-Tools, Hostname |
| `02_network.sh` | Statische Cluster-IP (Netplan) und Firewall (UFW) |
| `03_build_llamacpp.sh` | llama.cpp am festen Commit bauen |
| `04_rpc_worker.sh` | RPC-Server als Dienst `llama-rpc` (Worker) |
| `05_control_plane.sh` | API-Dienst `llama-server` und Hilfsbefehle (Control Plane) |
| `validate_cluster.sh` | Prüft Treiber, Build, Netz und Dienste |

Erzeugt auf den Nodes:

| Pfad | Inhalt |
|---|---|
| `/home/aiadmin/src/llama.cpp-rpc-sync` | Quellcode am festen Commit |
| `/home/aiadmin/build-llama-rpc-sync/bin` | `ggml-rpc-server`, `llama-cli`, `llama-server` |
| `/home/aiadmin/llama-rpc-sync.commit` | Gebauter Commit (Nachweis der Einheitlichkeit) |
| `/etc/netplan/60-llama-cluster.yaml` | Cluster-Interface mit statischer IP |
| `/etc/systemd/system/llama-rpc.service` | RPC-Dienst (Worker) |
| `/etc/systemd/system/llama-server.service` | API-Dienst (Control Plane) |
| `/etc/llama-cluster/api-keys` | API-Keys, einer pro Zeile (Control Plane) |
| `/usr/local/bin/llama-cluster-cli` | Multi-Node-Aufruf von `llama-cli` (Control Plane) |

## 3. Konfiguration (`cluster.conf`)

| Variable | Standard | Bedeutung |
|---|---|---|
| `CLUSTER_NODES` | `node-00:10.10.10.5:control`, `node-01..03:10.10.10.6..8:worker` | `hostname:ip:rolle`. Die Reihenfolge der Worker ergibt RPC0, RPC1, … **Hostnamen an die echten anpassen** |
| `LLAMA_COMMIT` | `daef7b68…` | llama.cpp-Stand für alle Nodes |
| `RPC_PORT` | `50052` | Port der RPC-Server |
| `RPC_CACHE` | `1` | Tensor-Cache auf den Workern: Nach einem Neustart wird das Modell nicht erneut übers Netz übertragen |
| `MODEL_HF` | Gemma 4 12B QAT Q4 | Hugging-Face-Repository und GGUF-Variante |
| `INFER_CTX` | `4096` | Kontextfenster in Tokens |
| `INFER_KV_TYPE` | `q8_0` | Quantisierung des KV-Caches |
| `SERVER_PORT` | `8080` | Port der API |
| `SERVER_HOST` | leer (= Cluster-IP) | Bind-Adresse der API. `0.0.0.0` = alle Interfaces |
| `SERVER_ALLOW_FROM` | `10.10.10.0/24` | Von wo die API erreichbar ist (UFW) |
| `SERVER_PARALLEL` | `1` | Gleichzeitige Anfragen (der Kontext wird auf die Slots aufgeteilt) |

Nach einer Änderung:
1. `cluster.conf` auf **alle** Nodes kopieren.
2. Je nach Variable das betroffene Skript erneut ausführen: Modell, Kontext und API → `05`, RPC-Port und Cache → `04` (+`05`), Commit → `03` (+`04`/`05`), Nodes → siehe Abschnitt 6.

## 4. Installation

Repo auf jeden Node kopieren (z. B. nach `/home/aiadmin/ClusterLLM`) und dort ausführen:

| Schritt | Wo | Befehl |
|---|---|---|
| 1 | alle | `sudo bash 01_system_setup.sh` → Reboot |
| 2 | alle | `sudo bash 02_network.sh` (Cluster-Interface wählen, mit ENTER bestätigen) |
| 3 | alle | `bash 03_build_llamacpp.sh` (als `aiadmin`, **ohne** sudo) |
| 4 | Worker | `sudo bash 04_rpc_worker.sh` |
| 5 | Control Plane | `sudo bash 05_control_plane.sh` (erst wenn alle Worker laufen) |
| 6 | alle | `bash validate_cluster.sh` |

### Umstieg von der manuellen Installation

Die bisher manuell eingerichteten Nodes (z. B. node-03) können die Skripte direkt nutzen:

- **Netplan:** Die Cluster-IP steht bisher in `/etc/netplan/50-cloud-init.yaml`. Den Block des Cluster-Interfaces dort entfernen, dann `02_network.sh` ausführen. Das Skript deaktiviert zusätzlich die Netzwerkverwaltung von cloud-init. Sonst kann `50-cloud-init.yaml` beim Boot neu erzeugt werden.
- **RPC-Server per `nohup`:** `04_rpc_worker.sh` beendet laufende `nohup`-Instanzen und übernimmt den Port als Dienst. Danach nie wieder per `nohup` starten.
- **Quellcode/Build:** Der vorhandene Clone in `~/src/llama.cpp-rpc-sync` wird weiterverwendet, `03` setzt ihn auf den Commit aus `cluster.conf`.
- **Aufräumen:** Ein alter Clone unter `/opt/llama.cpp` wird nicht mehr gebraucht: `sudo rm -rf /opt/llama.cpp`. Gleiches gilt für alte Logs `~/ggml-rpc-*.log`.

## 5. Bedienung

### Dienste

| Aufgabe | Worker | Control Plane |
|---|---|---|
| Status | `systemctl status llama-rpc` | `systemctl status llama-server` |
| Logs live | `journalctl -u llama-rpc -f` | `journalctl -u llama-server -f` |
| Neu starten | `sudo systemctl restart llama-rpc` | `sudo systemctl restart llama-server` |
| Stoppen | `sudo systemctl stop llama-rpc` | `sudo systemctl stop llama-server` |

Beide Dienste starten beim Booten automatisch und nach einem Absturz neu. Die Boot-Reihenfolge ist egal: `llama-server` wartet bis zu 5 Minuten, bis alle Worker erreichbar sind.

**Kompletter Neustart:** Worker neu starten, dann `sudo systemctl restart llama-server`. Oder einfach alle Nodes rebooten.

### API nutzen (OpenAI-kompatibel)

```bash
KEY=$(sudo grep -v '^#' /etc/llama-cluster/api-keys | head -1)
curl http://10.10.10.5:8080/v1/chat/completions \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"was ist 2 + 2"}],"max_tokens":64,"temperature":0}'
```

- Zustand: `curl http://10.10.10.5:8080/health` (ohne Key)
- Weitere Keys: eine Zeile in `/etc/llama-cluster/api-keys` ergänzen, dann `sudo systemctl restart llama-server`

### Direkter CLI-Test

Jeder RPC-Server bedient **nur einen Client**. Für `llama-cli` muss der API-Dienst deshalb pausieren:

```bash
sudo systemctl stop llama-server
llama-cluster-cli -p "was ist 2 + 2" -n 256 --seed 42 --temp 0
sudo systemctl start llama-server
```

### Überwachung

- GPU-Auslastung und VRAM: `nvitop` (oder `nvtop`, `nvidia-smi`)
- System: `btop`
- Netzlast während der Inferenz: `btop` (Netzwerk-Panel) auf dem Cluster-Interface

## 6. Wartung

**Modell wechseln:** `MODEL_HF` in `cluster.conf` ändern, dann auf der Control Plane `sudo bash 05_control_plane.sh` ausführen. Das Modell wird beim ersten Start heruntergeladen.

**llama.cpp aktualisieren:**
1. Neuen Commit in `cluster.conf` eintragen.
2. Auf **allen** Nodes nacheinander: `sudo systemctl stop llama-rpc llama-server`, dann `bash 03_build_llamacpp.sh`, dann `04` bzw. `05`.

RPC-Server und Client müssen exakt denselben Stand haben, sonst bricht die Verbindung mit „RPC server version mismatch“ ab.

**Treiber aktualisieren:** NVIDIA-Pakete sind von automatischen Updates ausgenommen. Updates nur bewusst einspielen, auf allen Nodes mit derselben Version, danach Reboot.

**Node hinzufügen:**
1. Den Node in `CLUSTER_NODES` eintragen und `cluster.conf` auf alle Nodes verteilen.
2. Auf dem neuen Node `01` bis `04` ausführen.
3. Auf der Control Plane `05` erneut ausführen.

Die Reihenfolge der Worker in der Liste bestimmt RPC0, RPC1, …

**Einheitlichkeit prüfen:** `bash validate_cluster.sh` auf der Control Plane vergleicht per SSH Commit und Treiber aller Nodes. Dafür ist ein SSH-Key-Login als `aiadmin` nötig: `ssh-copy-id aiadmin@10.10.10.x`.

## 7. Fehlerbehebung

| Symptom | Ursache / Lösung |
|---|---|
| `nvidia-smi`: „Driver/library version mismatch“ | Treiber wurde aktualisiert, ohne neu zu starten → `sudo reboot` |
| Build: „unsupported GNU version“ | Falscher Compiler → `03` verwenden (erzwingt GCC 10), ggf. `rm -rf ~/build-llama-rpc-sync` |
| Cluster-IP nach Reboot weg | cloud-init oder eine zweite Netplan-Datei → `02` erneut ausführen, `ip -br addr`, `ls /etc/netplan` |
| `llama-server` startet nicht, Log: „RPC-Server … nicht erreichbar“ | Worker aus, Dienst gestoppt oder Firewall → auf dem Worker `systemctl status llama-rpc` |
| „RPC server version mismatch“ | Nodes haben unterschiedliche llama.cpp-Stände → `validate_cluster.sh`, `03` neu bauen |
| `llama-cluster-cli` hängt beim Verbinden | `llama-server` belegt die RPC-Server → `sudo systemctl stop llama-server` |
| Out of memory (CUDA) | `INFER_CTX` verkleinern oder kleineres Modell/Quantisierung wählen |
| Erster Start dauert lange | Modell-Download; Fortschritt mit `journalctl -u llama-server -f` |
| Mehrere `ggml-rpc-server`-Prozesse | Alte `nohup`-Instanzen → `04` erneut ausführen |

## 8. Sicherheit

- Der RPC-Server ist laut llama.cpp **experimentell und ohne Authentifizierung**. Port 50052 ist auf jedem Worker nur für die IP der Control Plane offen. Diese Regel nicht lockern und das Cluster-Netz nicht mit anderen Netzen verbinden.
- Die API ist nur aus dem Cluster-Netz erreichbar und verlangt einen API-Key. Soll sie aus einem anderen Netz erreichbar sein, `SERVER_HOST=0.0.0.0` und `SERVER_ALLOW_FROM` passend setzen. Danach `02` und `05` erneut ausführen.
- Die Firewall-Regeln anzeigen: `sudo ufw status numbered`
