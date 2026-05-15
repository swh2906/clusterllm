from docx import Document
from docx.shared import Pt, RGBColor, Inches, Cm
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_ALIGN_VERTICAL
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

doc = Document()
for s in doc.sections:
    s.top_margin=Cm(2.5); s.bottom_margin=Cm(2.5)
    s.left_margin=Cm(2.8); s.right_margin=Cm(2.8)

NAVY=RGBColor(0x0D,0x1B,0x2A); CYAN=RGBColor(0x00,0xAE,0xEF)
WHITE=RGBColor(0xFF,0xFF,0xFF); LGREY=RGBColor(0xF2,0xF5,0xF8)
BLACK=RGBColor(0x10,0x18,0x20)

def shd_para(p,fill):
    pr=p._p.get_or_add_pPr(); s=OxmlElement("w:shd")
    s.set(qn("w:val"),"clear"); s.set(qn("w:color"),"auto"); s.set(qn("w:fill"),fill); pr.append(s)
def shd_cell(cell,fill):
    tc=cell._tc; pr=tc.get_or_add_tcPr(); s=OxmlElement("w:shd")
    s.set(qn("w:val"),"clear"); s.set(qn("w:color"),"auto"); s.set(qn("w:fill"),fill); pr.append(s)
def borders(table,color="00AEEF"):
    tbl=table._tbl; tp=tbl.find(qn("w:tblPr"))
    if tp is None: tp=OxmlElement("w:tblPr"); tbl.insert(0,tp)
    tb=OxmlElement("w:tblBorders")
    for side in ("top","left","bottom","right","insideH","insideV"):
        el=OxmlElement(f"w:{side}"); el.set(qn("w:val"),"single"); el.set(qn("w:sz"),"4")
        el.set(qn("w:space"),"0"); el.set(qn("w:color"),color); tb.append(el)
    tp.append(tb)
def h1(doc,text):
    p=doc.add_paragraph(); p.paragraph_format.space_before=Pt(20); p.paragraph_format.space_after=Pt(6)
    r=p.add_run(text); r.bold=True; r.font.size=Pt(17); r.font.color.rgb=CYAN; return p
def h2(doc,text):
    p=doc.add_paragraph(); p.paragraph_format.space_before=Pt(12); p.paragraph_format.space_after=Pt(4)
    r=p.add_run(text); r.bold=True; r.font.size=Pt(13); r.font.color.rgb=NAVY; return p
def body(doc,text):
    p=doc.add_paragraph(); p.paragraph_format.space_after=Pt(5)
    r=p.add_run(text); r.font.size=Pt(11); r.font.color.rgb=BLACK; return p
def bullet(doc,text):
    p=doc.add_paragraph(style="List Bullet"); p.paragraph_format.space_after=Pt(3)
    r=p.add_run(text); r.font.size=Pt(11); r.font.color.rgb=BLACK; return p
def numbered(doc,text):
    p=doc.add_paragraph(style="List Number"); p.paragraph_format.space_after=Pt(3)
    r=p.add_run(text); r.font.size=Pt(11); r.font.color.rgb=BLACK; return p
def code(doc,text):
    p=doc.add_paragraph(); p.paragraph_format.space_after=Pt(8); shd_para(p,"EEF4FB")
    r=p.add_run(text); r.font.name="Courier New"; r.font.size=Pt(9); r.font.color.rgb=NAVY; return p
def tbl(doc,headers,rows,widths=None):
    t=doc.add_table(rows=1+len(rows),cols=len(headers)); t.alignment=WD_TABLE_ALIGNMENT.LEFT; borders(t)
    for i,h in enumerate(headers):
        c=t.rows[0].cells[i]; shd_cell(c,"0D1B2A")
        r=c.paragraphs[0].add_run(h); r.bold=True; r.font.size=Pt(10); r.font.color.rgb=CYAN
    for ri,row in enumerate(rows):
        fill="F2F5F8" if ri%2==0 else "FFFFFF"
        for ci,val in enumerate(row):
            c=t.rows[ri+1].cells[ci]; shd_cell(c,fill); c.vertical_alignment=WD_ALIGN_VERTICAL.TOP
            r=c.paragraphs[0].add_run(str(val)); r.font.size=Pt(10); r.font.color.rgb=BLACK
    if widths:
        for i,w in enumerate(widths):
            for row in t.rows: row.cells[i].width=Inches(w)
    doc.add_paragraph(); return t

# COVER
for txt,sz,col,sp,bold in [
    ("SELF-HOSTED LLM CLUSTER",30,CYAN,50,True),
    ("Implementation Plan v3 \u2014 Kubernetes-First",18,WHITE,4,True),
    (" ",10,WHITE,4,False),
    ("Lenovo P1 Gen3  \u00b7  64 GB RAM  \u00b7  T1000 4 GB  \u00b7  k3s + llama.cpp",13,LGREY,4,False),
    ("Start 2 Nodes \u2192 Scale  \u00b7  Precise \u00b7 Fast \u00b7 Tunable \u00b7 On-Premise  |  2026",11,CYAN,4,False),
    (" ",28,WHITE,4,False),
]:
    p=doc.add_paragraph(); p.alignment=WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before=Pt(sp); p.paragraph_format.space_after=Pt(2)
    shd_para(p,"0D1B2A"); r=p.add_run(txt); r.font.size=Pt(sz); r.font.color.rgb=col; r.bold=bold
doc.add_page_break()

# TOC
h1(doc,"Table of Contents")
for num,title in [("1","Project Goal & Principles"),("2","Hardware"),("3","Architecture"),
    ("4","Technology Stack"),("5","Model Strategy"),
    ("6","Phase 1 \u2014 OS, Drivers & k3s Cluster"),
    ("7","Phase 2 \u2014 llama.cpp Container & GPU Scheduling"),
    ("8","Phase 3 \u2014 Serving Stack (Ingress + Load Balancing)"),
    ("9","Phase 4 \u2014 Fine-Tuning & Model Management"),
    ("10","Phase 5 \u2014 Scaling to More Nodes"),
    ("11","Performance Expectations"),("12","Customisation & Tuning"),("13","Risks & Mitigations")]:
    p=doc.add_paragraph(); p.paragraph_format.space_after=Pt(3)
    r=p.add_run(f"{num}.  {title}"); r.font.size=Pt(11); r.font.color.rgb=NAVY
doc.add_page_break()

# 1. GOAL
h1(doc,"1. Project Goal & Principles")
body(doc,"Build a self-hosted LLM cluster that works as a single unified machine. The cluster runs capable, fast, and precise language models that can be fine-tuned and customised on proprietary data. Kubernetes (k3s) is the foundation from day one \u2014 even with just 2 nodes \u2014 so every node added later requires zero architectural changes.")
h2(doc,"Core Requirements")
tbl(doc,["Requirement","Detail"],[
    ["Self-hosted & on-premise","No cloud dependency. All data, models, and compute stay local."],
    ["Kubernetes from day one","k3s on 2 nodes. Same architecture scales to 2, 5, 10, 20+ nodes without changes."],
    ["Capable LLMs","Run 7B\u201313B parameter models with high-quality output."],
    ["Fast inference","GPU-accelerated via llama.cpp CUDA offloading inside containers."],
    ["Precise & tunable","Fine-tune on custom data; adjust prompts, temperature, context window."],
    ["Single API endpoint","Kubernetes Service exposes one stable endpoint regardless of node count."],
    ["Automatic failover","If a node goes down, Kubernetes reschedules pods automatically."],
    ["Scalable","Add a node: join k3s, label it, pods schedule automatically."],
],widths=[2.2,5.0])
h2(doc,"Why Kubernetes from Day One?")
tbl(doc,["Concern","Answer"],[
    ["Is k3s overkill for 2 nodes?","No. k3s is a single binary, uses ~500 MB RAM, and runs fine on 64 GB nodes."],
    ["What do we gain immediately?","Automatic pod restarts, GPU resource scheduling, rolling model updates, one API endpoint."],
    ["What do we gain when scaling?","Add a node in 5 minutes. No nginx config changes. No manual service management."],
    ["What about complexity?","k3s is the simplest Kubernetes distribution. 2-3 kubectl commands to get started."],
],widths=[2.8,4.4])

# 2. HARDWARE
h1(doc,"2. Hardware")
h2(doc,"Per-Node Specification (confirmed)")
tbl(doc,["Component","Specification","Notes"],[
    ["CPU","Intel Core i7 vPro 10th Gen","6-core / 12-thread, up to 5.0 GHz boost"],
    ["RAM","64 GB DDR4","Excellent for KV cache, fine-tuning overflow, and OS+k3s overhead"],
    ["GPU","NVIDIA Quadro T1000 Max-Q","4 GB GDDR6 VRAM, 896 CUDA cores, CUDA 12 capable"],
    ["Storage","512 GB\u20131 TB NVMe SSD","OS + k3s + container images + GGUF model files"],
    ["Network","1 GbE Intel I219-LM","Sufficient for MVP; upgrade path via USB-C 10GbE adapter"],
    ["Display","node-00 has screen","All other nodes are headless"],
    ["OS","Ubuntu 22.04 LTS","Headless server install on all nodes"],
    ["Power","~45\u201365 W under load","~90\u2013130 W total for 2-node MVP"],
],widths=[1.8,2.4,3.0])
h2(doc,"Node Roles")
tbl(doc,["Node","Hostname","IP","Role"],[
    ["Node 0","node-00","192.168.10.10","k3s control plane + worker + admin access (has screen)"],
    ["Node 1","node-01","192.168.10.11","k3s worker (headless)"],
    ["Node N","node-0N","192.168.10.1N","k3s worker (headless) \u2014 add as needed"],
],widths=[0.8,1.2,1.6,3.6])
h2(doc,"2-Node MVP Additional Hardware")
tbl(doc,["Item","Qty","Notes"],[
    ["5- or 8-port 1GbE managed switch","1","e.g. TP-Link TL-SG105E (~\u20ac25)"],
    ["Cat6 Ethernet cables (2 m)","2","One per node to switch"],
    ["USB boot drives (16 GB)","2","Ubuntu Server install"],
    ["Power strip (4-outlet)","1","Both nodes + switch"],
],widths=[3.0,0.8,3.4])

# 3. ARCHITECTURE
h1(doc,"3. Architecture")
body(doc,"The cluster uses k3s as the control layer from day one. llama.cpp runs inside a container as a Kubernetes DaemonSet \u2014 one pod per node, each with exclusive access to the node GPU. A Kubernetes Service with nginx Ingress exposes a single stable API endpoint to clients.")
h2(doc,"Architecture Diagram")
code(doc,
    "  Client (app / browser / API)\n"
    "           |\n"
    "  [nginx Ingress Controller]  http://192.168.10.200/   <-- single stable endpoint\n"
    "           |\n"
    "  [Kubernetes Service: llama-service :8080]\n"
    "    /              \\\n"
    "[llama-pod node-00] [llama-pod node-01]  ...  [llama-pod node-0N]\n"
    "  GPU: T1000 4GB      GPU: T1000 4GB           GPU: T1000 4GB\n"
    "  llama-server:8080   llama-server:8080         llama-server:8080\n"
    "\n"
    "  k3s control plane: node-00  |  workers: node-01 ... node-0N\n"
    "  Subnet: 192.168.10.0/24  |  MetalLB pool: 192.168.10.200-220"
)
h2(doc,"Key Kubernetes Objects")
tbl(doc,["Object","Kind","Purpose"],[
    ["llama-server","DaemonSet","One llama.cpp pod per node. Each pod gets 1 GPU (nvidia.com/gpu: 1)."],
    ["llama-service","Service (ClusterIP)","Stable internal endpoint. Routes to all healthy llama pods."],
    ["llama-ingress","Ingress","Exposes the service on port 80 via nginx ingress controller."],
    ["llama-config","ConfigMap","Model path, server flags, system prompt. Update without rebuilding image."],
    ["model-storage","HostPath volume","GGUF model on each node NVMe at /opt/llama.cpp/models/. Fast, no NFS needed."],
],widths=[1.8,1.8,3.6])
h2(doc,"Why DaemonSet?")
body(doc,"A DaemonSet ensures exactly one llama pod runs on every GPU node automatically. When you add a new node and label it, the DaemonSet schedules a pod there with no manual intervention. Throughput scales linearly: 2 nodes = 2x capacity, 5 nodes = 5x capacity.")
h2(doc,"Scaling: What Changes When You Add a Node?")
tbl(doc,["Action","What Kubernetes Does Automatically"],[
    ["Join new node to k3s","Node appears in kubectl get nodes"],
    ["Label node: nvidia.com/gpu=true","DaemonSet schedules llama pod on new node"],
    ["Pod becomes Ready","Service automatically includes new pod in load balancing"],
    ["Nothing else needed","Cluster capacity increases, no config changes required"],
],widths=[2.8,4.4])

# 4. TECH STACK
h1(doc,"4. Technology Stack")
tbl(doc,["Layer","Component","Version","Role"],[
    ["OS","Ubuntu Server","22.04 LTS","Base OS, headless on all nodes"],
    ["GPU","NVIDIA Driver","535+","T1000 Max-Q support"],
    ["GPU","CUDA Toolkit","12.3","GPU compute runtime"],
    ["GPU","nvidia-container-toolkit","latest","GPU passthrough into k3s containers"],
    ["Kubernetes","k3s","v1.29+","Lightweight Kubernetes (single binary, ~500 MB RAM)"],
    ["GPU scheduling","NVIDIA Device Plugin","v0.14+","Exposes nvidia.com/gpu resource to k3s scheduler"],
    ["Networking","Flannel (built into k3s)","default","Pod-to-pod networking across nodes"],
    ["Load balancing","MetalLB","v0.14+","Bare-metal LoadBalancer for external IP assignment"],
    ["Ingress","nginx Ingress Controller","v1.9+","HTTP routing and load balancing across llama pods"],
    ["Inference","llama.cpp (llama-server)","latest","CUDA-accelerated LLM inference, OpenAI-compatible API"],
    ["Registry","registry:2 (local)","latest","Private container registry on node-00"],
    ["Fine-tuning","HuggingFace + PEFT + TRL","latest","QLoRA fine-tuning on custom data"],
    ["MLOps (scale)","KubeFlow","v1.8+","Add at 5+ nodes: job scheduling, pipelines, model registry"],
    ["Monitoring","Prometheus + Grafana","latest","Cluster and GPU metrics (add after MVP is stable)"],
],widths=[1.5,2.0,1.2,2.5])

# 5. MODEL STRATEGY
h1(doc,"5. Model Strategy")
body(doc,"With 4 GB VRAM and 64 GB RAM per node, llama.cpp splits model layers between GPU and CPU using the -ngl flag. The 64 GB RAM is a major advantage: it allows running 13B models with GPU+CPU split, and provides headroom for fine-tuning with QLoRA.")
h2(doc,"Recommended GGUF Models")
tbl(doc,["Model","Quant","File size","-ngl","VRAM","RAM overflow","Quality"],[
    ["Llama 3.1 8B Instruct","Q4_K_M","~4.7 GB","35 (all GPU)","~4.5 GB","0 GB","Very good \u2014 recommended start"],
    ["Mistral 7B Instruct v0.3","Q4_K_M","~4.1 GB","35 (all GPU)","~4.1 GB","0 GB","Excellent instruction following"],
    ["Llama 3.1 13B Instruct","Q4_K_M","~7.5 GB","20 (GPU+CPU)","~4.0 GB","~3.5 GB","Best quality, slightly slower"],
    ["Phi-3 Mini 3.8B","Q4_K_M","~2.3 GB","35 (all GPU)","~2.3 GB","0 GB","Fastest, good reasoning"],
    ["CodeLlama 7B Instruct","Q4_K_M","~4.1 GB","35 (all GPU)","~4.1 GB","0 GB","Code generation & automation"],
],widths=[2.0,1.0,1.1,1.3,1.1,1.3,2.3])
body(doc,"Start with: Llama 3.1 8B Instruct Q4_K_M. All 35 layers fit on the T1000 GPU. Fast (~18-25 t/s per node), high quality, best fine-tuning base. Source: bartowski/Meta-Llama-3.1-8B-Instruct-GGUF on HuggingFace.")

# 6. PHASE 1
h1(doc,"6. Phase 1 \u2014 OS, Drivers & k3s Cluster (2 Nodes)")
body(doc,"Estimated time: 3\u20135 hours. Goal: both nodes running Ubuntu with NVIDIA drivers and a healthy k3s cluster.")
h2(doc,"1.1 OS Installation")
numbered(doc,"Flash 2x USB drives with Ubuntu Server 22.04 LTS. Disable Secure Boot in BIOS on both nodes.")
numbered(doc,"Install Ubuntu Server on node-00: hostname=node-00, static IP=192.168.10.10/24, SSH enabled, no GUI.")
numbered(doc,"Install Ubuntu Server on node-01: hostname=node-01, static IP=192.168.10.11/24, SSH enabled, no GUI.")
numbered(doc,"On both nodes: sudo apt update && sudo apt upgrade -y")
numbered(doc,"Add /etc/hosts entries on both nodes: 192.168.10.10 node-00 and 192.168.10.11 node-01.")
numbered(doc,"Generate SSH key on node-00 and copy to node-01: ssh-keygen -t ed25519 && ssh-copy-id ubuntu@node-01")
h2(doc,"1.2 NVIDIA Drivers & CUDA (both nodes)")
code(doc,
    "wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb\n"
    "sudo dpkg -i cuda-keyring_1.1-1_all.deb && sudo apt update\n"
    "sudo apt install -y nvidia-driver-535 cuda-toolkit-12-3 nvidia-container-toolkit\n"
    "sudo reboot\n"
    "nvidia-smi  # expect: Quadro T1000, 4096 MiB, Driver 535.x"
)
h2(doc,"1.3 Install k3s")
code(doc,
    "# node-00: install k3s SERVER (control plane + worker), disable built-in traefik\n"
    "curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644 --disable traefik\n\n"
    "# Get node token for workers\n"
    "sudo cat /var/lib/rancher/k3s/server/node-token\n\n"
    "# node-01: install k3s AGENT\n"
    "curl -sfL https://get.k3s.io | K3S_URL=https://192.168.10.10:6443 K3S_TOKEN=<TOKEN> sh -\n\n"
    "# node-00: verify cluster\n"
    "kubectl get nodes -o wide  # both nodes STATUS=Ready"
)
h2(doc,"1.4 Configure nvidia-container-toolkit for k3s containerd")
code(doc,
    "# On ALL nodes: configure containerd runtime for NVIDIA\n"
    "sudo nvidia-ctk runtime configure --runtime=containerd\n"
    "sudo systemctl restart k3s          # node-00\n"
    "sudo systemctl restart k3s-agent    # node-01\n\n"
    "# Verify\n"
    "grep -A5 'nvidia' /var/lib/rancher/k3s/agent/etc/containerd/config.toml"
)
h2(doc,"1.5 Deploy NVIDIA Device Plugin")
code(doc,
    "kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.0/nvidia-device-plugin.yml\n\n"
    "# Wait for DaemonSet pods\n"
    "kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds\n\n"
    "# Verify GPU resource visible on each node\n"
    "kubectl get nodes -o json | grep -A4 'nvidia.com/gpu'\n"
    "# Expect: \"nvidia.com/gpu\": \"1\" per node"
)
h2(doc,"1.6 Deploy MetalLB")
code(doc,
    "kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.3/config/manifests/metallb-native.yaml\n"
    "kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=90s\n\n"
    "# Configure IP pool\n"
    "cat <<EOF | kubectl apply -f -\n"
    "apiVersion: metallb.io/v1beta1\n"
    "kind: IPAddressPool\n"
    "metadata:\n"
    "  name: cluster-pool\n"
    "  namespace: metallb-system\n"
    "spec:\n"
    "  addresses:\n"
    "  - 192.168.10.200-192.168.10.220\n"
    "---\n"
    "apiVersion: metallb.io/v1beta1\n"
    "kind: L2Advertisement\n"
    "metadata:\n"
    "  name: cluster-l2\n"
    "  namespace: metallb-system\n"
    "EOF"
)
h2(doc,"1.7 Validate GPU Scheduling")
code(doc,
    "kubectl run gpu-test --image=nvidia/cuda:12.3.0-base-ubuntu22.04 \\\n"
    "  --restart=Never --limits='nvidia.com/gpu=1' -- nvidia-smi\n"
    "kubectl logs gpu-test  # expect: T1000 4096 MiB\n"
    "kubectl delete pod gpu-test"
)
h2(doc,"Phase 1 Acceptance Criteria")
tbl(doc,["Check","Expected Result"],[
    ["kubectl get nodes","Both nodes: STATUS=Ready"],
    ["nvidia-smi on both nodes","T1000, 4096 MiB, Driver 535.x"],
    ["kubectl get nodes (GPU capacity)","nvidia.com/gpu: 1 on each node"],
    ["GPU test pod logs","nvidia-smi output showing T1000"],
    ["MetalLB pods","All Running in metallb-system namespace"],
],widths=[2.8,4.4])

# 7. PHASE 2
h1(doc,"7. Phase 2 \u2014 llama.cpp Container & GPU Scheduling")
body(doc,"Estimated time: 2\u20133 hours. Goal: llama.cpp running as a Kubernetes DaemonSet with one GPU-accelerated pod per node.")
h2(doc,"2.1 Build llama.cpp on Each Node")
code(doc,
    "# Run on ALL nodes\n"
    "sudo apt install -y build-essential cmake git\n"
    "git clone https://github.com/ggerganov/llama.cpp /opt/llama.cpp\n"
    "cd /opt/llama.cpp && cmake -B build -DGGML_CUDA=ON\n"
    "cmake --build build --config Release -j$(nproc)\n"
    "mkdir -p /opt/llama.cpp/models\n"
    "./build/bin/llama-server --version  # verify"
)
h2(doc,"2.2 Download Model to All Nodes")
code(doc,
    "# node-00: download\n"
    "pip install huggingface_hub\n"
    "huggingface-cli download bartowski/Meta-Llama-3.1-8B-Instruct-GGUF \\\n"
    "  Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf --local-dir /opt/llama.cpp/models/\n\n"
    "# Sync to workers\n"
    "rsync -avz --progress /opt/llama.cpp/models/ ubuntu@node-01:/opt/llama.cpp/models/"
)
h2(doc,"2.3 Create Namespace and ConfigMap")
code(doc,
    "kubectl create namespace llm\n\n"
    "cat <<EOF | kubectl apply -f -\n"
    "apiVersion: v1\n"
    "kind: ConfigMap\n"
    "metadata:\n"
    "  name: llama-config\n"
    "  namespace: llm\n"
    "data:\n"
    "  MODEL_PATH: /opt/llama.cpp/models/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf\n"
    "  N_GPU_LAYERS: \"35\"\n"
    "  CONTEXT_SIZE: \"4096\"\n"
    "  PARALLEL: \"4\"\n"
    "  PORT: \"8080\"\n"
    "EOF"
)
h2(doc,"2.4 Deploy llama-server DaemonSet")
code(doc,
    "cat <<EOF | kubectl apply -f -\n"
    "apiVersion: apps/v1\n"
    "kind: DaemonSet\n"
    "metadata:\n"
    "  name: llama-server\n"
    "  namespace: llm\n"
    "spec:\n"
    "  selector:\n"
    "    matchLabels:\n"
    "      app: llama-server\n"
    "  template:\n"
    "    metadata:\n"
    "      labels:\n"
    "        app: llama-server\n"
    "    spec:\n"
    "      containers:\n"
    "      - name: llama-server\n"
    "        image: ubuntu:22.04\n"
    "        command: [\"/opt/llama.cpp/build/bin/llama-server\"]\n"
    "        args: [\"-m\",\"/opt/llama.cpp/models/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf\",\n"
    "               \"-ngl\",\"35\",\"-c\",\"4096\",\"--host\",\"0.0.0.0\",\n"
    "               \"--port\",\"8080\",\"--parallel\",\"4\",\"--cont-batching\"]\n"
    "        ports:\n"
    "        - containerPort: 8080\n"
    "        resources:\n"
    "          limits:\n"
    "            nvidia.com/gpu: 1\n"
    "            memory: 16Gi\n"
    "          requests:\n"
    "            memory: 8Gi\n"
    "        volumeMounts:\n"
    "        - name: llama-bin\n"
    "          mountPath: /opt/llama.cpp\n"
    "        livenessProbe:\n"
    "          httpGet:\n"
    "            path: /health\n"
    "            port: 8080\n"
    "          initialDelaySeconds: 30\n"
    "          periodSeconds: 15\n"
    "      volumes:\n"
    "      - name: llama-bin\n"
    "        hostPath:\n"
    "          path: /opt/llama.cpp\n"
    "          type: Directory\n"
    "EOF\n\n"
    "kubectl get pods -n llm -o wide -w  # watch pods come up"
)
h2(doc,"Phase 2 Acceptance Criteria")
tbl(doc,["Check","Expected Result"],[
    ["kubectl get pods -n llm","One llama-server pod per node, STATUS=Running"],
    ["Pod logs","'llama server listening' on :8080, 'offloaded 35/35 layers to GPU'"],
    ["Health check via pod IP","curl <pod-ip>:8080/health returns {\"status\":\"ok\"}"],
    ["GPU usage","nvidia-smi shows ~4 GB VRAM used on each node"],
],widths=[2.8,4.4])

# 8. PHASE 3
h1(doc,"8. Phase 3 \u2014 Serving Stack (Ingress + Load Balancing)")
body(doc,"Estimated time: 1 hour. Goal: a single stable API endpoint at http://192.168.10.200/ that load-balances across all llama pods.")
h2(doc,"3.1 Deploy nginx Ingress Controller")
code(doc,
    "kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.6/deploy/static/provider/baremetal/deploy.yaml\n"
    "kubectl wait --namespace ingress-nginx --for=condition=ready pod \\\n"
    "  --selector=app.kubernetes.io/component=controller --timeout=120s\n\n"
    "# Patch to use MetalLB LoadBalancer (gives clean port 80 endpoint)\n"
    "kubectl patch svc ingress-nginx-controller -n ingress-nginx \\\n"
    "  -p '{\"spec\":{\"type\":\"LoadBalancer\"}}'\n"
    "kubectl get svc -n ingress-nginx  # MetalLB assigns 192.168.10.200"
)
h2(doc,"3.2 Create Service and Ingress")
code(doc,
    "cat <<EOF | kubectl apply -f -\n"
    "apiVersion: v1\n"
    "kind: Service\n"
    "metadata:\n"
    "  name: llama-service\n"
    "  namespace: llm\n"
    "spec:\n"
    "  selector:\n"
    "    app: llama-server\n"
    "  ports:\n"
    "  - port: 8080\n"
    "    targetPort: 8080\n"
    "  type: ClusterIP\n"
    "---\n"
    "apiVersion: networking.k8s.io/v1\n"
    "kind: Ingress\n"
    "metadata:\n"
    "  name: llama-ingress\n"
    "  namespace: llm\n"
    "  annotations:\n"
    "    nginx.ingress.kubernetes.io/proxy-read-timeout: \"300\"\n"
    "    nginx.ingress.kubernetes.io/proxy-send-timeout: \"300\"\n"
    "spec:\n"
    "  ingressClassName: nginx\n"
    "  rules:\n"
    "  - http:\n"
    "      paths:\n"
    "      - path: /\n"
    "        pathType: Prefix\n"
    "        backend:\n"
    "          service:\n"
    "            name: llama-service\n"
    "            port:\n"
    "              number: 8080\n"
    "EOF"
)
h2(doc,"3.3 Test the Cluster Endpoint")
code(doc,
    "# Single endpoint, load balanced across all llama pods\n"
    "curl http://192.168.10.200/v1/chat/completions \\\n"
    "  -H 'Content-Type: application/json' \\\n"
    "  -d '{\"model\":\"llama\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello!\"}]}'\n\n"
    "# Failover test: delete one pod, requests still served\n"
    "kubectl delete pod -n llm -l app=llama-server --field-selector spec.nodeName=node-01\n"
    "curl http://192.168.10.200/health  # still returns ok\n"
    "kubectl get pods -n llm -w  # watch pod restart automatically"
)
h2(doc,"Phase 3 Acceptance Criteria")
tbl(doc,["Check","Expected Result"],[
    ["Single endpoint test","curl http://192.168.10.200/v1/chat/completions returns LLM response"],
    ["Load balancing","Requests distributed across both node pods"],
    ["Failover test","Delete one pod; requests still served; pod auto-restarts"],
    ["Auto-recovery","Restarted pod rejoins load balancing automatically"],
],widths=[2.8,4.4])

# 9. PHASE 4
h1(doc,"9. Phase 4 \u2014 Fine-Tuning & Model Management")
body(doc,"Fine-tune the base model on your own data and deploy the result as a rolling update across the cluster. Zero downtime during model swap.")
h2(doc,"Fine-Tuning Workflow")
numbered(doc,"Prepare dataset in JSONL format: {\"instruction\": \"...\", \"output\": \"...\"} per line. Minimum 100 examples.")
numbered(doc,"Install fine-tuning dependencies on node-00: pip install torch transformers datasets peft bitsandbytes trl accelerate")
numbered(doc,"Run QLoRA fine-tuning script on node-00 (uses GPU + 64 GB RAM). Expect 1-4 hours for 1000 examples.")
numbered(doc,"Merge LoRA adapters: AutoPeftModelForCausalLM.from_pretrained('./output').merge_and_unload()")
numbered(doc,"Convert to GGUF: python /opt/llama.cpp/convert_hf_to_gguf.py ./merged_model --outtype q4_k_m --outfile finetuned-Q4_K_M.gguf")
numbered(doc,"Test locally: ./build/bin/llama-cli -m finetuned-Q4_K_M.gguf -ngl 35 -p 'Test prompt' -n 128")
numbered(doc,"rsync new GGUF to all nodes: rsync -avz finetuned-Q4_K_M.gguf ubuntu@node-01:/opt/llama.cpp/models/")
numbered(doc,"Update ConfigMap MODEL_PATH and trigger rolling restart:")
code(doc,
    "kubectl patch configmap llama-config -n llm --type merge \\\n"
    "  -p '{\"data\":{\"MODEL_PATH\":\"/opt/llama.cpp/models/finetuned-Q4_K_M.gguf\"}}'\n\n"
    "# Rolling restart: one pod at a time, cluster stays available\n"
    "kubectl rollout restart daemonset/llama-server -n llm\n"
    "kubectl rollout status daemonset/llama-server -n llm\n\n"
    "# Rollback if needed\n"
    "kubectl rollout undo daemonset/llama-server -n llm"
)

# 10. PHASE 5
h1(doc,"10. Phase 5 \u2014 Scaling to More Nodes")
body(doc,"Adding a new node takes approximately 30 minutes. The DaemonSet automatically schedules a new llama pod on the new node with no other changes required.")
h2(doc,"Adding a New Node (10 Steps)")
numbered(doc,"Install Ubuntu Server 22.04 on new node. Set hostname=node-0N, static IP=192.168.10.1N.")
numbered(doc,"Add new hostname/IP to /etc/hosts on all existing nodes and the new node.")
numbered(doc,"Install NVIDIA driver 535 + CUDA 12 + nvidia-container-toolkit. Reboot. Validate with nvidia-smi.")
numbered(doc,"Build llama.cpp with CUDA on the new node (same cmake commands as Phase 2.1).")
numbered(doc,"rsync model files from node-00: rsync -avz node-00:/opt/llama.cpp/models/ /opt/llama.cpp/models/")
numbered(doc,"Configure nvidia-ctk for containerd: sudo nvidia-ctk runtime configure --runtime=containerd")
numbered(doc,"Join the new node to k3s: curl -sfL https://get.k3s.io | K3S_URL=https://192.168.10.10:6443 K3S_TOKEN=<TOKEN> sh -")
numbered(doc,"Verify node is Ready: kubectl get nodes")
numbered(doc,"DaemonSet automatically schedules llama pod on new node. Watch: kubectl get pods -n llm -o wide")
numbered(doc,"New node starts receiving traffic automatically via the Service. No other changes needed.")
h2(doc,"Scaling Milestones")
tbl(doc,["Nodes","Add These Components","Reason"],[
    ["2 (MVP)","k3s + DaemonSet + nginx Ingress + MetalLB","This document. Full Kubernetes from day one."],
    ["3\u20135","Ansible playbook for node provisioning","Automate the 10-step add-node process"],
    ["5+","KubeFlow Pipelines + Training Operator","Manage fine-tuning jobs as Kubernetes workloads"],
    ["5+","MLflow + MinIO","Experiment tracking and model artifact storage"],
    ["8+","Upgrade to 10GbE switch + NICs","If model rsync or inter-pod traffic becomes a bottleneck"],
    ["10+","k3s HA control plane (3 control nodes)","Eliminate single point of failure on node-00"],
    ["10+","Prometheus + Grafana + DCGM Exporter","Full GPU and cluster observability"],
],widths=[1.0,2.8,3.4])

# 11. PERFORMANCE
h1(doc,"11. Performance Expectations")
tbl(doc,["Model","Quant","-ngl","t/s per node","t/s 2 nodes (parallel)","Notes"],[
    ["Llama 3.1 8B","Q4_K_M","35","~18\u201325","~36\u201350","Recommended start"],
    ["Mistral 7B","Q4_K_M","35","~20\u201328","~40\u201356","Fastest 7B"],
    ["Llama 3.1 13B","Q4_K_M","20","~8\u201312","~16\u201324","Best quality, GPU+CPU split"],
    ["Phi-3 Mini 3.8B","Q4_K_M","35","~35\u201345","~70\u201390","Fastest overall"],
],widths=[1.8,1.0,0.8,1.6,2.2,2.0])
body(doc,"Throughput scales linearly with nodes for concurrent users. Each node handles its own requests independently. Adding a 3rd node adds another ~18-25 t/s of parallel capacity.")

# 12. CUSTOMISATION
h1(doc,"12. Customisation & Tuning")
body(doc,"All tuning parameters are stored in the llama-config ConfigMap. Change a value, rolling-restart the DaemonSet \u2014 no image rebuild needed.")
tbl(doc,["Parameter","Effect","Recommended"],[
    ["-ngl N","GPU layers offloaded. Higher = faster, more VRAM.","35 for 8B Q4_K_M (all layers)"],
    ["-c N","Context window. Larger = more memory per slot.","4096 default; 8192 if needed"],
    ["--parallel N","Concurrent request slots per pod.","4 (safe for 64 GB RAM)"],
    ["--cont-batching","Batch multiple requests in one forward pass.","Always enable"],
    ["--temp 0.x","Sampling temperature. Lower = more precise.","0.1\u20130.3 for factual/automation tasks"],
    ["--repeat-penalty","Reduces output repetition.","1.1 default"],
    ["system prompt","Sets model persona and behaviour.","Customise per use case in ConfigMap"],
],widths=[2.0,2.8,2.4])

# 13. RISKS
h1(doc,"13. Risks & Mitigations")
tbl(doc,["Risk","Likelihood","Mitigation"],[
    ["T1000 4 GB VRAM too small for a specific model","Low","Use Q4_K_M + lower -ngl to split to 64 GB RAM; or switch to smaller model"],
    ["node-00 control plane failure","Low","Promote node-01 to control plane; add HA control plane at 10+ nodes"],
    ["Pod crash loop (OOM or driver issue)","Low","Kubernetes auto-restarts pod; livenessProbe detects and restarts on hang"],
    ["Model quality insufficient","Medium","Fine-tune on domain data (Phase 4); or upgrade to 13B model"],
    ["NVIDIA driver / containerd incompatibility","Low","Pin driver version; test nvidia-ctk config before deploying DaemonSet"],
    ["1 GbE bottleneck","Low","Only affects model rsync (one-time); inference is fully local per node"],
    ["Fine-tuning OOM on 64 GB RAM","Low","Reduce batch size to 1, enable gradient checkpointing, use Q4 base model"],
],widths=[2.4,1.1,3.7])

out = r"C:\Users\Shau\artifacts\LLM_Cluster_Plan_v3.docx"
doc.save(out)
print(f"Saved: {out}")
