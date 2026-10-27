# ClusterLLM — llama.cpp RPC-Cluster

Verteilte LLM-Inferenz mit llama.cpp über RPC auf Ubuntu 22.04.5 LTS (Turing-GPUs, CC 7.5).

**Bedienung und Konfiguration: [DOKU.md](DOKU.md)**

Kurzfassung: `cluster.conf` anpassen und auf alle Nodes kopieren, dann `01` bis `03` auf allen Nodes ausführen, `04` auf den Workern, `05` auf der Control Plane und zum Schluss `validate_cluster.sh`.
