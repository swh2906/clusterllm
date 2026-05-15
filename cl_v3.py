from docx import Document
from docx.shared import Pt, RGBColor, Inches, Cm
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_ALIGN_VERTICAL
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

doc = Document()
for s in doc.sections:
    s.top_margin=Cm(2.0); s.bottom_margin=Cm(2.0)
    s.left_margin=Cm(2.2); s.right_margin=Cm(2.2)

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
    p=doc.add_paragraph(); p.paragraph_format.space_before=Pt(16); p.paragraph_format.space_after=Pt(4)
    r=p.add_run(text); r.bold=True; r.font.size=Pt(14); r.font.color.rgb=CYAN; return p
def body(doc,text):
    p=doc.add_paragraph(); p.paragraph_format.space_after=Pt(4)
    r=p.add_run(text); r.font.size=Pt(10); r.font.color.rgb=BLACK; return p
def phase_banner(doc,text):
    p=doc.add_paragraph(); p.paragraph_format.space_before=Pt(12); p.paragraph_format.space_after=Pt(2)
    shd_para(p,"0D1B2A"); r=p.add_run(f"  {text}")
    r.bold=True; r.font.size=Pt(11); r.font.color.rgb=CYAN; return p

def cl_table(doc,items):
    # cols: checkbox | # | Task | Command / Notes
    t=doc.add_table(rows=1+len(items),cols=4); t.alignment=WD_TABLE_ALIGNMENT.LEFT; borders(t)
    ws=[Inches(0.28),Inches(0.32),Inches(3.0),Inches(3.6)]
    for i,h in enumerate(["\u2713","#","Task","Command / Notes"]):
        c=t.rows[0].cells[i]; shd_cell(c,"0D1B2A"); c.width=ws[i]
        r=c.paragraphs[0].add_run(h); r.bold=True; r.font.size=Pt(10); r.font.color.rgb=CYAN
    for ri,(num,task,notes) in enumerate(items):
        row=t.rows[ri+1]; fill="F2F5F8" if ri%2==0 else "FFFFFF"
        for ci,val in enumerate(["\u25a1",str(num),task,notes]):
            c=row.cells[ci]; shd_cell(c,fill); c.width=ws[ci]
            c.vertical_alignment=WD_ALIGN_VERTICAL.TOP
            r=c.paragraphs[0].add_run(val)
            if ci==0: r.font.size=Pt(13); r.font.color.rgb=CYAN
            elif ci==1: r.font.size=Pt(10); r.bold=True; r.font.color.rgb=CYAN
            elif ci==2: r.font.size=Pt(10); r.font.color.rgb=BLACK
            else: r.font.size=Pt(8.5); r.font.name="Courier New"; r.font.color.rgb=NAVY
    doc.add_paragraph(); return t

# COVER
for txt,sz,col,sp,bold in [
    ("LLM CLUSTER BUILD CHECKLIST",26,CYAN,40,True),
    ("Kubernetes-First \u00b7 k3s + llama.cpp \u00b7 2 Nodes \u2192 Scale",15,WHITE,4,True),
    (" ",10,WHITE,4,False),
    ("Lenovo P1 Gen3  \u00b7  64 GB RAM  \u00b7  T1000 4 GB  \u00b7  i7 vPro 10th Gen",12,LGREY,4,False),
    ("Precise \u00b7 Fast \u00b7 Tunable \u00b7 Fully On-Premise  |  2026",10,CYAN,4,False),
    (" ",24,WHITE,4,False),
]:
    p=doc.add_paragraph(); p.alignment=WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before=Pt(sp); p.paragraph_format.space_after=Pt(2)
    shd_para(p,"0D1B2A"); r=p.add_run(txt); r.font.size=Pt(sz); r.font.color.rgb=col; r.bold=bold
doc.add_page_break()

h1(doc,"How to Use This Checklist")
body(doc,"Work through each phase in order. Tick \u25a1 when done. Every step has the exact command. Do not skip steps \u2014 each is a dependency for the next.")
body(doc,"Hardware: Lenovo P1 Gen3  \u00b7  Intel i7 vPro 10th Gen  \u00b7  64 GB DDR4  \u00b7  NVIDIA Quadro T1000 4 GB VRAM Max-Q  \u00b7  Ubuntu 22.04 LTS")
body(doc,"Start: 2 nodes (node-00 with screen = control plane, node-01 headless = worker). To add more nodes: repeat Phase C+D+E+F for each new node, then run step 90.")
doc.add_paragraph()

# PHASE A — HARDWARE
phase_banner(doc,"PHASE A \u2014 Hardware & Physical Setup")
cl_table(doc,[
    (1,"Connect both nodes to switch with Cat6 cables","node-00 and node-01 \u2192 switch \u2192 router/internet"),
    (2,"Disable Secure Boot in BIOS on both nodes","Required for NVIDIA proprietary driver installation"),
    (3,"Set boot order: USB first, then NVMe","Needed for Ubuntu install"),
    (4,"Flash 2x USB drives with Ubuntu Server 22.04 LTS ISO","balenaEtcher or Rufus  \u00b7  ubuntu.com/download/server"),
])

# PHASE B — OS
phase_banner(doc,"PHASE B \u2014 OS Installation (both nodes)")
cl_table(doc,[
    (5, "Install Ubuntu Server on node-00","hostname: node-00  \u00b7  IP: 192.168.10.10/24  \u00b7  GW: 192.168.10.1  \u00b7  SSH: yes  \u00b7  no GUI"),
    (6, "Install Ubuntu Server on node-01","hostname: node-01  \u00b7  IP: 192.168.10.11/24  \u00b7  GW: 192.168.10.1  \u00b7  SSH: yes  \u00b7  no GUI"),
    (7, "Update packages on both nodes","sudo apt update && sudo apt upgrade -y"),
    (8, "Add /etc/hosts entries on node-00","echo '192.168.10.11 node-01' | sudo tee -a /etc/hosts"),
    (9, "Add /etc/hosts entries on node-01","echo '192.168.10.10 node-00' | sudo tee -a /etc/hosts"),
    (10,"Generate SSH key on node-00","ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ''"),
    (11,"Copy SSH public key to node-01","ssh-copy-id ubuntu@node-01"),
    (12,"Test passwordless SSH from node-00 to node-01","ssh node-01 hostname  # should print: node-01"),
    (13,"Ping test between nodes","ping -c 3 node-01  (from node-00)"),
])

# PHASE C — GPU DRIVERS
phase_banner(doc,"PHASE C \u2014 GPU Drivers & CUDA (both nodes)")
cl_table(doc,[
    (14,"Add NVIDIA CUDA apt keyring on both nodes","wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb && sudo dpkg -i cuda-keyring_1.1-1_all.deb"),
    (15,"Update apt","sudo apt update"),
    (16,"Install NVIDIA driver 535","sudo apt install -y nvidia-driver-535"),
    (17,"Install CUDA 12.3 toolkit","sudo apt install -y cuda-toolkit-12-3"),
    (18,"Install nvidia-container-toolkit","sudo apt install -y nvidia-container-toolkit"),
    (19,"Reboot both nodes","sudo reboot"),
    (20,"Validate GPU on node-00","nvidia-smi  # expect: Quadro T1000, 4096 MiB, Driver 535.x"),
    (21,"Validate GPU on node-01","ssh node-01 nvidia-smi  # same expected output"),
    (22,"Check CUDA version","nvcc --version  # expect: release 12.3"),
])

# PHASE D — BUILD llama.cpp
phase_banner(doc,"PHASE D \u2014 Build llama.cpp with CUDA (both nodes)")
cl_table(doc,[
    (23,"Install build dependencies on both nodes","sudo apt install -y build-essential cmake git"),
    (24,"Clone llama.cpp on both nodes","git clone https://github.com/ggerganov/llama.cpp /opt/llama.cpp"),
    (25,"Configure cmake with CUDA enabled","cd /opt/llama.cpp && cmake -B build -DGGML_CUDA=ON"),
    (26,"Compile llama.cpp (uses all CPU cores, ~5-10 min)","cmake --build build --config Release -j$(nproc)"),
    (27,"Verify build succeeded","./build/bin/llama-server --version"),
    (28,"Create models directory on both nodes","mkdir -p /opt/llama.cpp/models"),
])

# PHASE E — DOWNLOAD MODEL
phase_banner(doc,"PHASE E \u2014 Download Model & Test Inference")
cl_table(doc,[
    (29,"Install huggingface_hub on node-00","pip install huggingface_hub"),
    (30,"Download Llama 3.1 8B Instruct Q4_K_M GGUF (~4.7 GB)","huggingface-cli download bartowski/Meta-Llama-3.1-8B-Instruct-GGUF Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf --local-dir /opt/llama.cpp/models/"),
    (31,"Run quick CLI inference test on node-00","cd /opt/llama.cpp && ./build/bin/llama-cli -m models/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf -ngl 35 -c 2048 -p 'What is 2+2?' -n 64"),
    (32,"Confirm output shows 'offloaded 35/35 layers to GPU'","Look for this line in the llama-cli output"),
    (33,"Check GPU memory usage during inference","nvidia-smi  # VRAM used should be ~4.0-4.5 GB"),
    (34,"Copy model to node-01 via rsync","rsync -avz --progress /opt/llama.cpp/models/ ubuntu@node-01:/opt/llama.cpp/models/"),
    (35,"Test inference on node-01","ssh node-01 'cd /opt/llama.cpp && ./build/bin/llama-cli -m models/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf -ngl 35 -p \"Hello\" -n 32'"),
])

# PHASE F — k3s CLUSTER
phase_banner(doc,"PHASE F \u2014 k3s Kubernetes Cluster")
cl_table(doc,[
    (36,"Install k3s server on node-00 (control plane + worker, traefik disabled)","curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644 --disable traefik"),
    (37,"Verify k3s is running on node-00","sudo systemctl status k3s  # should show: active (running)"),
    (38,"Get k3s node token from node-00","sudo cat /var/lib/rancher/k3s/server/node-token  # copy this value"),
    (39,"Install k3s agent on node-01 (replace TOKEN)","curl -sfL https://get.k3s.io | K3S_URL=https://192.168.10.10:6443 K3S_TOKEN=<TOKEN> sh -"),
    (40,"Verify both nodes are Ready","kubectl get nodes -o wide  # both STATUS=Ready within 60s"),
    (41,"Configure nvidia-container-toolkit for k3s containerd on node-00","sudo nvidia-ctk runtime configure --runtime=containerd && sudo systemctl restart k3s"),
    (42,"Configure nvidia-container-toolkit for k3s containerd on node-01","ssh node-01 'sudo nvidia-ctk runtime configure --runtime=containerd && sudo systemctl restart k3s-agent'"),
    (43,"Deploy NVIDIA Device Plugin DaemonSet","kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.0/nvidia-device-plugin.yml"),
    (44,"Wait for NVIDIA Device Plugin pods to be Running","kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds  # both Running"),
    (45,"Verify GPU resource visible on each node","kubectl get nodes -o json | grep -A4 'nvidia.com/gpu'  # expect: \"nvidia.com/gpu\": \"1\" per node"),
    (46,"Run GPU test pod to validate scheduling","kubectl run gpu-test --image=nvidia/cuda:12.3.0-base-ubuntu22.04 --restart=Never --limits='nvidia.com/gpu=1' -- nvidia-smi"),
    (47,"Check GPU test pod logs","kubectl logs gpu-test  # expect: T1000 4096 MiB"),
    (48,"Delete GPU test pod","kubectl delete pod gpu-test"),
])

# PHASE G — MetalLB
phase_banner(doc,"PHASE G \u2014 MetalLB Bare-Metal Load Balancer")
cl_table(doc,[
    (49,"Deploy MetalLB","kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.3/config/manifests/metallb-native.yaml"),
    (50,"Wait for MetalLB pods to be Running","kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=90s"),
    (51,"Create MetalLB IP address pool (save as metallb-pool.yaml and apply)","apiVersion: metallb.io/v1beta1 / kind: IPAddressPool / addresses: [192.168.10.200-192.168.10.220]"),
    (52,"Create MetalLB L2Advertisement (save as metallb-l2.yaml and apply)","apiVersion: metallb.io/v1beta1 / kind: L2Advertisement / namespace: metallb-system"),
    (53,"Verify MetalLB is ready","kubectl get ipaddresspool -n metallb-system"),
])

# PHASE H — llama DaemonSet
phase_banner(doc,"PHASE H \u2014 llama-server DaemonSet (Kubernetes)")
cl_table(doc,[
    (54,"Create llm namespace","kubectl create namespace llm"),
    (55,"Create llama-config ConfigMap (save as llama-config.yaml and apply)","kind: ConfigMap / data: MODEL_PATH, N_GPU_LAYERS: 35, CONTEXT_SIZE: 4096, PARALLEL: 4, PORT: 8080"),
    (56,"Create llama-server DaemonSet (save as llama-daemonset.yaml and apply)","kind: DaemonSet / image: ubuntu:22.04 / command: llama-server / resources.limits: nvidia.com/gpu: 1 / volumeMounts: /opt/llama.cpp (hostPath)"),
    (57,"Watch DaemonSet pods come up (one per node)","kubectl get pods -n llm -o wide -w  # both pods STATUS=Running"),
    (58,"Check pod logs for GPU offload confirmation","kubectl logs -n llm -l app=llama-server  # look for 'offloaded 35/35 layers to GPU'"),
    (59,"Test health endpoint via pod IP","kubectl get pods -n llm -o wide  # get pod IP, then: curl <pod-ip>:8080/health"),
    (60,"Verify GPU usage on both nodes","nvidia-smi  # VRAM ~4 GB used on each node"),
])

# PHASE I — INGRESS & SERVICE
phase_banner(doc,"PHASE I \u2014 nginx Ingress & Single Cluster Endpoint")
cl_table(doc,[
    (61,"Deploy nginx Ingress Controller (bare-metal)","kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.6/deploy/static/provider/baremetal/deploy.yaml"),
    (62,"Wait for ingress controller pod to be Ready","kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s"),
    (63,"Patch ingress controller to use MetalLB LoadBalancer","kubectl patch svc ingress-nginx-controller -n ingress-nginx -p '{\"spec\":{\"type\":\"LoadBalancer\"}}'"),
    (64,"Get assigned external IP (should be 192.168.10.200)","kubectl get svc -n ingress-nginx ingress-nginx-controller  # EXTERNAL-IP: 192.168.10.200"),
    (65,"Create llama-service (ClusterIP, save as llama-service.yaml and apply)","kind: Service / selector: app=llama-server / port: 8080 / type: ClusterIP"),
    (66,"Create llama-ingress (save as llama-ingress.yaml and apply)","kind: Ingress / ingressClassName: nginx / path: / -> llama-service:8080 / proxy-read-timeout: 300"),
    (67,"Test the single cluster endpoint","curl http://192.168.10.200/v1/chat/completions -H 'Content-Type: application/json' -d '{\"model\":\"llama\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello!\"}]}'"),
    (68,"Send 10 requests and verify both pods serve traffic","for i in $(seq 1 10); do curl -s http://192.168.10.200/health; done"),
    (69,"Failover test: delete one pod, verify cluster still responds","kubectl delete pod -n llm <pod-name> && curl http://192.168.10.200/health  # still ok"),
    (70,"Verify deleted pod auto-restarts","kubectl get pods -n llm -w  # pod restarts automatically"),
    (71,"Reboot both nodes and confirm auto-start","sudo reboot  # wait, then: curl http://192.168.10.200/health"),
])

# PHASE J — VALIDATE & TUNE
phase_banner(doc,"PHASE J \u2014 Validate & Tune the Cluster")
cl_table(doc,[
    (72,"Run 5 quality test prompts via cluster endpoint","curl http://192.168.10.200/v1/chat/completions with factual questions"),
    (73,"Measure tokens/sec on a long generation","./build/bin/llama-cli -m models/*.gguf -ngl 35 -p 'Write a 500 word essay' -n 500 2>&1 | grep 'eval time'"),
    (74,"Tune -ngl: try 30, 33, 35 and compare speed","Lower -ngl = more CPU, less VRAM. 35 is optimal for 8B Q4_K_M on T1000."),
    (75,"Tune context size: test -c 2048, 4096, 8192","Larger context uses more RAM. 4096 is safe default with 64 GB RAM."),
    (76,"Tune --parallel: test 2, 4, 8 concurrent slots","Higher parallel = more RAM used. 4 is safe for 64 GB."),
    (77,"Update ConfigMap with final tuned values","kubectl patch configmap llama-config -n llm --type merge -p '{\"data\":{\"N_GPU_LAYERS\":\"35\",\"CONTEXT_SIZE\":\"4096\",\"PARALLEL\":\"4\"}}'"),
    (78,"Rolling restart DaemonSet to apply ConfigMap changes","kubectl rollout restart daemonset/llama-server -n llm"),
    (79,"Monitor rollout progress","kubectl rollout status daemonset/llama-server -n llm"),
    (80,"Set a custom system prompt for your use case in ConfigMap","Add SYSTEM_PROMPT key to llama-config ConfigMap, then rolling restart"),
    (81,"Document final working configuration","Save final ConfigMap YAML to /opt/cluster-config/llama-config.yaml"),
])

# PHASE K — FINE-TUNING
phase_banner(doc,"PHASE K \u2014 Fine-Tune on Your Own Data (node-00)")
cl_table(doc,[
    (82,"Install Python fine-tuning dependencies on node-00","pip install torch transformers datasets peft bitsandbytes trl accelerate"),
    (83,"Prepare training data in JSONL format","Each line: {\"instruction\": \"...\", \"output\": \"...\"}  \u2014  min 100 examples recommended"),
    (84,"Write QLoRA fine-tuning script (finetune.py)","AutoModelForCausalLM(load_in_4bit=True) + LoraConfig(r=16, lora_alpha=32) + SFTTrainer"),
    (85,"Run fine-tuning on node-00","python finetune.py  # uses GPU + 64 GB RAM; expect 1-4 hours for 1000 examples"),
    (86,"Monitor GPU and RAM usage during training","watch -n 2 nvidia-smi  # VRAM ~3.5-4 GB; htop for RAM"),
    (87,"Wait for training to complete (loss should decrease steadily)","Check output/trainer_state.json for final loss value"),
    (88,"Merge LoRA adapters into base model","python merge.py  # AutoPeftModelForCausalLM.from_pretrained('./output').merge_and_unload()"),
    (89,"Install GGUF conversion requirements","pip install -r /opt/llama.cpp/requirements/requirements-convert_hf_to_gguf.txt"),
    (90,"Convert merged model to GGUF Q4_K_M","python /opt/llama.cpp/convert_hf_to_gguf.py ./merged_model --outtype q4_k_m --outfile finetuned-Q4_K_M.gguf"),
    (91,"Test fine-tuned model locally","./build/bin/llama-cli -m finetuned-Q4_K_M.gguf -ngl 35 -p 'Test prompt from your domain' -n 128"),
    (92,"Copy fine-tuned model to all nodes","rsync -avz finetuned-Q4_K_M.gguf ubuntu@node-01:/opt/llama.cpp/models/"),
    (93,"Update ConfigMap MODEL_PATH to fine-tuned model","kubectl patch configmap llama-config -n llm --type merge -p '{\"data\":{\"MODEL_PATH\":\"/opt/llama.cpp/models/finetuned-Q4_K_M.gguf\"}}'"),
    (94,"Rolling restart to deploy fine-tuned model (zero downtime)","kubectl rollout restart daemonset/llama-server -n llm"),
    (95,"Monitor rollout","kubectl rollout status daemonset/llama-server -n llm"),
    (96,"Validate fine-tuned model via cluster endpoint","curl http://192.168.10.200/v1/chat/completions with domain-specific prompt"),
    (97,"Rollback if needed","kubectl rollout undo daemonset/llama-server -n llm"),
])

# PHASE L — ADD A NODE
phase_banner(doc,"PHASE L \u2014 Add a New Node (repeat per additional node)")
cl_table(doc,[
    (98, "Install Ubuntu Server 22.04 on new node","hostname: node-0N  \u00b7  IP: 192.168.10.1N  \u00b7  SSH enabled"),
    (99, "Add new node to /etc/hosts on all existing nodes","echo '192.168.10.1N node-0N' | sudo tee -a /etc/hosts  (on all nodes)"),
    (100,"Copy SSH key from node-00 to new node","ssh-copy-id ubuntu@node-0N"),
    (101,"Install NVIDIA driver 535 + CUDA 12 + nvidia-container-toolkit on new node","(same as Phase C steps 14-22)"),
    (102,"Build llama.cpp with CUDA on new node","(same as Phase D steps 23-28)"),
    (103,"rsync model files from node-00 to new node","rsync -avz /opt/llama.cpp/models/ ubuntu@node-0N:/opt/llama.cpp/models/"),
    (104,"Configure nvidia-ctk for containerd on new node","sudo nvidia-ctk runtime configure --runtime=containerd"),
    (105,"Join new node to k3s cluster","curl -sfL https://get.k3s.io | K3S_URL=https://192.168.10.10:6443 K3S_TOKEN=<TOKEN> sh -"),
    (106,"Verify new node is Ready","kubectl get nodes  # new node STATUS=Ready"),
    (107,"DaemonSet auto-schedules llama pod on new node","kubectl get pods -n llm -o wide  # new pod appears automatically"),
    (108,"Verify new node receives traffic","kubectl logs -n llm <new-pod-name>  # should show inference requests"),
])

# PHASE M — MONITORING
phase_banner(doc,"PHASE M \u2014 Basic Monitoring (recommended)")
cl_table(doc,[
    (109,"Install htop and nvtop on all nodes","sudo apt install -y htop nvtop"),
    (110,"Monitor GPU usage in real time","nvtop  # GPU utilisation, VRAM, temperature per node"),
    (111,"Check DaemonSet pod logs","kubectl logs -n llm -l app=llama-server --tail=50"),
    (112,"Check pod resource usage","kubectl top pods -n llm  # requires metrics-server"),
    (113,"Install metrics-server for kubectl top","kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"),
    (114,"Set up cron health check on node-00 (optional)","*/5 * * * * curl -sf http://192.168.10.200/health || kubectl rollout restart daemonset/llama-server -n llm"),
    (115,"Deploy Prometheus + Grafana when cluster is stable (optional)","helm install kube-prom prometheus-community/kube-prometheus-stack"),
    (116,"Deploy NVIDIA DCGM Exporter for GPU metrics (optional)","kubectl apply -f https://raw.githubusercontent.com/NVIDIA/dcgm-exporter/main/deployment/dcgm-exporter.yaml"),
])

# SUMMARY TABLE
doc.add_page_break()
h1(doc,"Summary: What You Have After Each Phase")
t=doc.add_table(rows=1+10,cols=3); t.alignment=WD_TABLE_ALIGNMENT.LEFT; borders(t)
for i,h in enumerate(["After Phase","You Have","Est. Time"]):
    c=t.rows[0].cells[i]; shd_cell(c,"0D1B2A")
    r=c.paragraphs[0].add_run(h); r.bold=True; r.font.size=Pt(10); r.font.color.rgb=CYAN
rows=[
    ("A","Hardware connected, BIOS configured, USB drives ready","30 min"),
    ("B","Both nodes running Ubuntu, SSH access, static IPs","2-3 hours"),
    ("C","NVIDIA drivers + CUDA working on both nodes","1-2 hours"),
    ("D","llama.cpp compiled with CUDA on both nodes","30-60 min"),
    ("E","Model downloaded, GPU inference working locally","1-2 hours (download)"),
    ("F","k3s cluster running, GPU scheduling validated","1-2 hours"),
    ("G","MetalLB ready, external IPs available","20 min"),
    ("H","llama-server DaemonSet running, one GPU pod per node","30-60 min"),
    ("I","Single cluster endpoint at 192.168.10.200, load balanced, auto-failover","30 min"),
    ("J-K","Tuned, fine-tuned model serving your use case via Kubernetes","1-3 days (training)"),
]
for ri,row_data in enumerate(rows):
    row=t.rows[ri+1]; fill="F2F5F8" if ri%2==0 else "FFFFFF"
    for ci,val in enumerate(row_data):
        c=row.cells[ci]; shd_cell(c,fill)
        r=c.paragraphs[0].add_run(val); r.font.size=Pt(10); r.font.color.rgb=BLACK
        if ci==0: r.bold=True; r.font.color.rgb=CYAN
for row in t.rows:
    row.cells[0].width=Inches(1.1); row.cells[1].width=Inches(4.8); row.cells[2].width=Inches(1.3)
doc.add_paragraph()
body(doc,"Total time to a working 2-node Kubernetes LLM cluster: approximately 1-2 days.")
body(doc,"Adding each additional node: approximately 30-45 minutes (once you have the process memorised).")
body(doc,"Key advantage of Kubernetes from day one: adding node 3, 4, or 10 requires zero changes to the serving stack. The DaemonSet and Service handle everything automatically.")

out = r"C:\Users\Shau\artifacts\LLM_Cluster_Checklist_v3.docx"
doc.save(out)
print(f"Saved: {out}")
