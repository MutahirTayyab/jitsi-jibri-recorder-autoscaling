# Jitsi + Jibri Recorder Autoscaling Project

This project documents a Docker-based Jitsi Meet and Jibri recording setup with automated recorder scaling.  
The system runs Jitsi Meet on a dedicated server and runs multiple Jibri recorder containers on a separate recorder server.

Jibri recorders are automatically started based on recorder availability. The autoscaler keeps one recorder warm and starts another recorder when all active recorders are busy.

---

## Architecture

```mermaid
flowchart LR
    U[Doctor / Patient Browser] -->|HTTPS| W[Jitsi Meet Web]

    subgraph JITSI[Jitsi Server]
        W[Jitsi Web]
        P[Prosody XMPP]
        F[Jicofo Focus]
        V[Jitsi Videobridge]
    end

    subgraph JIBRI[Jibri Recorder Server]
        A[Autoscaler Script]
        T[Systemd Timer]
        J1[Jibri Recorder 1]
        J2[Jibri Recorder 2]
        J3[Jibri Recorder 3]
        JN[Jibri Recorder N]
        R[(Host-Mounted Recordings Folder)]
    end

    W --> P
    F --> P
    F -->|Selects available recorder| P
    J1 -->|Joins Jibri Brewery MUC| P
    J2 -->|Joins Jibri Brewery MUC| P
    J3 -->|Joins Jibri Brewery MUC| P
    JN -->|Joins Jibri Brewery MUC| P

    J1 -->|WebRTC Media| V
    J2 -->|WebRTC Media| V
    J3 -->|WebRTC Media| V
    JN -->|WebRTC Media| V

    T --> A
    A -->|Checks health API| J1
    A -->|Checks health API| J2
    A -->|Starts / stops idle recorders| J3
    A -->|Scales up to max configured recorders| JN

    J1 --> R
    J2 --> R
    J3 --> R
    JN --> R
````

---

## Main Features

* Docker Compose based Jitsi Meet deployment
* Separate Jibri recorder server
* Multiple Jibri recorder containers
* Autoscaling based on Jibri `busyStatus`
* Keeps one recorder warm and ready
* Starts new recorder when no idle recorder is available
* Stops extra idle recorders after timeout
* Supports up to 30 configured Jibri containers
* Recordings persisted on the host server using Docker volume mounts
* Systemd timer used to run autoscaler automatically
* Includes safe `.env.example` files without production secrets

---

## Repository Structure

```text
.
├── docs/
│   └── Jitsi_Jibri_Recorder_Autoscaling_Documentation_Updated.docx
├── jitsi-vm/
│   ├── docker-compose.yml
│   └── .env.example
├── jibri-vm/
│   ├── jibri.yml
│   ├── .env.example
│   ├── asoundrc/
│   ├── finalize/
│   │   └── finalize.sh
│   ├── scripts/
│   │   └── jibri-autoscaler.sh
│   └── systemd/
│       ├── jibri-autoscaler.service
│       └── jibri-autoscaler.timer
├── .gitignore
└── README.md
```

---

## Scaling Logic

The autoscaler does not scale based on CPU, RAM, doctor appointments, or general website traffic.

It scales based on Jibri recorder availability:

```text
If no IDLE recorder is available,
and all running recorders are BUSY or starting,
then start the next Jibri container.
```

Default behavior:

```text
Minimum running recorders: 1
Maximum running recorders: 30
Idle timeout: 10 minutes
Check interval: 20 seconds
```

Example:

```text
jibri1 is IDLE
Doctor starts recording
jibri1 becomes BUSY
autoscaler starts jibri2
jibri2 stays IDLE as warm spare
```

---

## Recording Persistence

Recordings are not stored only inside the container.

Each Jibri container uses a host-mounted recording folder:

```yaml
./recordings/jibri1:/config/recordings
```

This means:

```text
Container stops      = recordings remain saved
Container crashes    = recordings remain saved
Container is removed = recordings remain saved
```

Recordings are saved on the Jibri server under host folders such as:

```text
recordings/jibri1/
recordings/jibri2/
recordings/jibri3/
```

To verify saved recordings:

```bash
find recordings -type f -name "*.mp4" -ls
```

---

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/MutahirTayyab/jitsi-jibri-recorder-autoscaling.git
cd jitsi-jibri-recorder-autoscaling
```

---

### 2. Prepare Jitsi Server

```bash
cd jitsi-vm
cp .env.example .env
vi .env
```

Update values such as:

```env
PUBLIC_URL=https://your-domain.example.com
JVB_ADVERTISE_IPS=YOUR_PRIVATE_IP,YOUR_PUBLIC_IP
DOCKER_HOST_ADDRESS=YOUR_PRIVATE_IP
```

Start Jitsi:

```bash
docker compose -f docker-compose.yml up -d
```

---

### 3. Prepare Jibri Server

```bash
cd jibri-vm
cp .env.example .env
vi .env
```

Make sure the Jibri passwords match the Jitsi `.env` values.

Start one recorder first:

```bash
docker compose -f jibri.yml up -d jibri1
```

Check health:

```bash
curl -s http://127.0.0.1:2222/jibri/api/v1.0/health | jq .
```

Expected:

```json
{
  "status": {
    "busyStatus": "IDLE",
    "health": {
      "healthStatus": "HEALTHY",
      "details": {}
    }
  }
}
```

---

### 4. Install Autoscaler

Copy autoscaler script:

```bash
sudo cp scripts/jibri-autoscaler.sh /usr/local/bin/jibri-autoscaler.sh
sudo chmod +x /usr/local/bin/jibri-autoscaler.sh
```

Copy systemd files:

```bash
sudo cp systemd/jibri-autoscaler.service /etc/systemd/system/
sudo cp systemd/jibri-autoscaler.timer /etc/systemd/system/
```

Enable timer:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now jibri-autoscaler.timer
```

Check timer:

```bash
systemctl status jibri-autoscaler.timer
```

Watch autoscaler logs:

```bash
journalctl -u jibri-autoscaler.service -f
```

---

## Useful Commands

Check running Jibri containers:

```bash
docker compose -f jibri.yml ps
```

Check all recorder health:

```bash
for i in $(seq 1 30); do
  port=$((2221+i))
  echo -n "jibri$i => "
  curl -s --max-time 3 http://127.0.0.1:$port/jibri/api/v1.0/health \
    | jq -r '"health=" + .status.health.healthStatus + " busy=" + .status.busyStatus' \
    || echo "NO RESPONSE"
done
```

Start a specific recorder:

```bash
docker compose -f jibri.yml up -d jibri5
```

Stop a specific recorder:

```bash
docker compose -f jibri.yml stop jibri5
```

Stop all recorders:

```bash
docker compose -f jibri.yml down --remove-orphans
```

---

## Notes

1. One Jibri container can handle one active recording at a time.
2. Multiple simultaneous recordings require multiple Jibri containers.
3. The autoscaler starts new recorders only when no idle recorder is available.
4. Extra idle recorders are stopped after the configured timeout.
5. Recordings remain saved on the Jibri host because Docker host-mounted volumes are used.
6. Server resources should be monitored when increasing recorder count.
