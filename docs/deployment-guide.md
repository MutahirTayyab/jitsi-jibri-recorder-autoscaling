Create this file in your repo:

```text
docs/deployment-guide.md
```

Paste this content:

````md
# Deployment Guide

This guide explains how to deploy the final Jitsi + Jibri recorder autoscaling setup.

The project uses two separate servers:

```text
Jitsi Server  -> web, prosody, jicofo, jvb
Jibri Server  -> multiple Jibri recorder containers + autoscaler
````

The Jibri recorders are scaled based on recorder availability. The autoscaler keeps one recorder warm and starts another recorder when no IDLE recorder is available.

---

## Step 1: Prepare Servers

Create or prepare two Linux servers:

```text
Jitsi Server  -> Jitsi Meet core services
Jibri Server  -> Jibri recorder containers
```

Recommended firewall rules for the Jitsi server:

```text
22/tcp       from admin IP only
80/tcp       from public
443/tcp      from public
10000/udp    from public and Jibri server
5222/tcp     from Jibri server only
ICMP         optional, from Jibri server only for testing
```

The Jibri server does not need public web ports. It mainly needs outbound access to the Jitsi server and internet.

Recommended Jibri server access:

```text
22/tcp       from admin IP only
Outbound     allowed to Jitsi server and internet
```

---

## Step 2: DNS

Create an A record for the Jitsi domain:

```text
your-domain.example.com -> Jitsi server public IP
```

Use this domain in `PUBLIC_URL`.

Do not build the production setup around a raw IP address.

Example:

```env
PUBLIC_URL=https://your-domain.example.com
```

---

## Step 3: Install Docker

Install Docker Engine and Docker Compose plugin on both servers.

```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg unzip
sudo install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update

sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo systemctl enable docker
sudo systemctl start docker

docker --version
docker compose version
```

Optional: allow the current user to run Docker without `sudo`:

```bash
sudo usermod -aG docker $USER
newgrp docker
```

---

## Step 4: Deploy Jitsi Server

On the Jitsi server:

```bash
cd jitsi-vm
cp .env.example .env
vi .env
```

Update the required values:

```env
PUBLIC_URL=https://your-domain.example.com

JVB_ADVERTISE_IPS=JITSI_PRIVATE_IP,JITSI_PUBLIC_IP
JVB_ADVERTISE_PRIVATE_CANDIDATES=1
DOCKER_HOST_ADDRESS=JITSI_PRIVATE_IP

ENABLE_RECORDING=1
ENABLE_FILE_RECORDING_SERVICE=1
ENABLE_SERVICE_RECORDING=1
ENABLE_LIVESTREAMING=1

XMPP_DOMAIN=meet.jitsi
XMPP_AUTH_DOMAIN=auth.meet.jitsi
XMPP_INTERNAL_MUC_DOMAIN=internal-muc.meet.jitsi
XMPP_MUC_DOMAIN=muc.meet.jitsi
XMPP_RECORDER_DOMAIN=recorder.meet.jitsi
XMPP_HIDDEN_DOMAIN=recorder.meet.jitsi

JIBRI_RECORDER_USER=recorder
JIBRI_XMPP_USER=jibri
JIBRI_BREWERY_MUC=jibribrewery
JIBRI_PENDING_TIMEOUT=90
```

Set strong passwords for:

```env
JICOFO_AUTH_PASSWORD=CHANGE_ME
JVB_AUTH_PASSWORD=CHANGE_ME
JIBRI_RECORDER_PASSWORD=CHANGE_ME
JIBRI_XMPP_PASSWORD=CHANGE_ME
```

Start Jitsi:

```bash
docker compose -f docker-compose.yml up -d
```

Verify containers:

```bash
docker compose ps
```

Expected services:

```text
web
prosody
jicofo
jvb
```

---

## Step 5: Register Jibri Users in Prosody

On the Jitsi server, register the Jibri XMPP user and recorder user.

```bash
docker compose exec prosody prosodyctl --config /config/prosody.cfg.lua register jibri auth.meet.jitsi 'JIBRI_XMPP_PASSWORD_FROM_ENV' || true

docker compose exec prosody prosodyctl --config /config/prosody.cfg.lua register recorder recorder.meet.jitsi 'JIBRI_RECORDER_PASSWORD_FROM_ENV' || true
```

Restart Prosody and Jicofo:

```bash
docker compose restart prosody jicofo
```

Check logs:

```bash
docker compose logs --tail=100 prosody
docker compose logs --tail=100 jicofo
```

---

## Step 6: Prepare Jibri Server Packages

On the Jibri server:

```bash
sudo apt update
sudo apt install -y curl jq alsa-utils tcpdump
sudo apt install -y linux-modules-extra-$(uname -r) || true
```

Check Docker:

```bash
docker --version
docker compose version
```

---

## Step 7: Configure ALSA Loopback for Jibri

Each Jibri recorder requires an ALSA loopback device.

For 30 configured recorders:

```bash
sudo bash -c 'cat > /etc/modprobe.d/alsa-loopback.conf <<EOF
options snd-aloop enable=1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1 index=0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29
EOF'
```

Load the module on boot:

```bash
echo "snd-aloop" | sudo tee /etc/modules-load.d/snd-aloop.conf
```

Reload:

```bash
sudo modprobe -r snd_aloop || true
sudo modprobe snd-aloop
```

Verify:

```bash
aplay -l | grep -i loopback
arecord -l | grep -i loopback
```

If loopback devices do not appear correctly, reboot the Jibri server:

```bash
sudo reboot
```

After reconnecting:

```bash
aplay -l | grep -i loopback
```

---

## Step 8: Deploy Jibri Server Files

On the Jibri server:

```bash
cd jibri-vm
cp .env.example .env
vi .env
```

Update required values:

```env
PUBLIC_URL=https://your-domain.example.com
XMPP_SERVER=JITSI_PRIVATE_IP
XMPP_PORT=5222

XMPP_DOMAIN=meet.jitsi
XMPP_AUTH_DOMAIN=auth.meet.jitsi
XMPP_INTERNAL_MUC_DOMAIN=internal-muc.meet.jitsi
XMPP_MUC_DOMAIN=muc.meet.jitsi
XMPP_RECORDER_DOMAIN=recorder.meet.jitsi
XMPP_HIDDEN_DOMAIN=recorder.meet.jitsi

JIBRI_XMPP_USER=jibri
JIBRI_XMPP_PASSWORD=SAME_AS_JITSI_ENV

JIBRI_RECORDER_USER=recorder
JIBRI_RECORDER_PASSWORD=SAME_AS_JITSI_ENV

JIBRI_BREWERY_MUC=jibribrewery
JIBRI_STRIP_DOMAIN_JID=muc
JIBRI_PENDING_TIMEOUT=90

JIBRI_RECORDING_DIR=/config/recordings
JIBRI_SINGLE_USE_MODE=false
DISPLAY=:0
CHROMIUM_FLAGS=--ignore-certificate-errors
```

Important:

```env
XMPP_SERVER=JITSI_PRIVATE_IP
```

Do not use the internal Docker hostname from the Jitsi server.

---

## Step 9: Prepare Jibri Runtime Folders

From the `jibri-vm` directory:

```bash
mkdir -p config recordings logs

for i in $(seq 1 30); do
  mkdir -p config/jibri$i
  mkdir -p recordings/jibri$i
  mkdir -p logs/jibri$i
done
```

Make sure the finalize script is executable:

```bash
chmod +x finalize/finalize.sh
```

---

## Step 10: Start One Jibri Recorder First

Start only one recorder first:

```bash
docker compose -f jibri.yml up -d jibri1
```

Check container:

```bash
docker compose -f jibri.yml ps
```

Check health:

```bash
curl -s http://127.0.0.1:2222/jibri/api/v1.0/health | jq .
```

Expected result:

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

If the health check returns `HEALTHY` and `IDLE`, the first recorder is ready.

---

## Step 11: Connectivity Checks

From the Jibri server:

```bash
nc -zv your-domain.example.com 443
nc -zv JITSI_PRIVATE_IP 5222
```

Test the Jitsi web URL:

```bash
curl -Ik https://your-domain.example.com
```

If `5222` fails, check firewall rules and Prosody port exposure on the Jitsi server.

---

## Step 12: Media Path Verification

If Jibri joins the room but recording fails after around 30 seconds, check the media path.

On the Jitsi server:

```bash
sudo tcpdump -ni any "host JIBRI_PRIVATE_IP and udp port 10000"
```

On the Jibri server:

```bash
sudo tcpdump -ni any "udp port 10000"
```

Start recording and observe traffic.

Correct behavior:

```text
Jibri server sends UDP traffic to Jitsi private IP on port 10000.
Jitsi server receives UDP traffic from Jibri private IP.
```

If Jibri sends media traffic to the public IP and ICE fails, confirm this on the Jitsi server:

```env
JVB_ADVERTISE_IPS=JITSI_PRIVATE_IP,JITSI_PUBLIC_IP
JVB_ADVERTISE_PRIVATE_CANDIDATES=1
```

Then restart:

```bash
docker compose up -d --force-recreate jvb jicofo
```

---

## Step 13: Recording Test

Open the Jitsi domain in the browser:

```text
https://your-domain.example.com
```

Create a room, join as moderator, and start recording.

On the Jibri server, watch logs:

```bash
docker compose -f jibri.yml logs -f jibri1
```

During recording, health should show:

```bash
curl -s http://127.0.0.1:2222/jibri/api/v1.0/health | jq .
```

Expected:

```json
{
  "status": {
    "busyStatus": "BUSY",
    "health": {
      "healthStatus": "HEALTHY"
    }
  }
}
```

Stop the recording and check saved files:

```bash
find recordings -type f -name "*.mp4" -ls
```

Recordings are saved on the Jibri server through host-mounted folders, not only inside containers.

Example host paths:

```text
recordings/jibri1/
recordings/jibri2/
recordings/jibri3/
```

---

## Step 14: Enable Jibri Autoscaler

Copy the autoscaler script:

```bash
sudo cp scripts/jibri-autoscaler.sh /usr/local/bin/jibri-autoscaler.sh
sudo chmod +x /usr/local/bin/jibri-autoscaler.sh
```

Copy systemd files:

```bash
sudo cp systemd/jibri-autoscaler.service /etc/systemd/system/
sudo cp systemd/jibri-autoscaler.timer /etc/systemd/system/
```

Enable the timer:

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

Manual autoscaler test:

```bash
sudo /usr/local/bin/jibri-autoscaler.sh
```

Expected output example:

```text
jibri1 health=HEALTHY busy=IDLE
running=1 idle=1 busy=0 starting=0
```

---

## Step 15: Scale Testing

Start with a small number first:

```bash
docker compose -f jibri.yml up -d jibri1 jibri2 jibri3
```

Check health:

```bash
for i in $(seq 1 3); do
  port=$((2221+i))
  echo -n "jibri$i => "
  curl -s --max-time 3 http://127.0.0.1:$port/jibri/api/v1.0/health \
    | jq -r '"health=" + .status.health.healthStatus + " busy=" + .status.busyStatus' \
    || echo "NO RESPONSE"
done
```

Start all configured recorders if required:

```bash
docker compose -f jibri.yml up -d
```

Check all:

```bash
for i in $(seq 1 30); do
  port=$((2221+i))
  echo -n "jibri$i => "
  curl -s --max-time 3 http://127.0.0.1:$port/jibri/api/v1.0/health \
    | jq -r '"health=" + .status.health.healthStatus + " busy=" + .status.busyStatus' \
    || echo "NO RESPONSE"
done
```

---

## Step 16: Operational Commands

Check Jitsi services:

```bash
docker compose ps
```

Check Jibri services:

```bash
docker compose -f jibri.yml ps
```

View Jibri logs:

```bash
docker compose -f jibri.yml logs -f jibri1
```

Check one Jibri health:

```bash
curl -s http://127.0.0.1:2222/jibri/api/v1.0/health | jq .
```

Check all Jibri health:

```bash
for i in $(seq 1 30); do
  port=$((2221+i))
  echo -n "jibri$i => "
  curl -s --max-time 3 http://127.0.0.1:$port/jibri/api/v1.0/health \
    | jq -r '"health=" + .status.health.healthStatus + " busy=" + .status.busyStatus' \
    || echo "NO RESPONSE"
done
```

Stop autoscaler:

```bash
sudo systemctl stop jibri-autoscaler.timer
sudo systemctl stop jibri-autoscaler.service
```

Start autoscaler:

```bash
sudo systemctl enable --now jibri-autoscaler.timer
```

Stop all Jibri containers:

```bash
docker compose -f jibri.yml down --remove-orphans
```

Start only one Jibri:

```bash
docker compose -f jibri.yml up -d jibri1
```

---

## Step 17: Security Notes

Do not upload or expose:

```text
real .env files
real passwords
VM credentials
SSL private keys
PEM files
recording files
logs
runtime config folders
```

Use `.env.example` as the template and generate your own secrets for production.

---

## Step 18: Important Notes

1. One Jibri container can handle one active recording at a time.
2. Multiple simultaneous recordings require multiple Jibri containers.
3. Autoscaling is based on Jibri `busyStatus`, not CPU/RAM usage.
4. At least one recorder should remain running as a warm spare.
5. Extra idle recorders are stopped after the configured idle timeout.
6. Recordings are persisted on the Jibri server using host-mounted Docker volumes.
7. Jibri must be able to reach the Jitsi server on HTTPS, XMPP port 5222, and JVB UDP port 10000.
8. Server resources should be monitored carefully when increasing the number of recorder containers.

```
```
