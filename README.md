# 🎥 Jitsi + Jibri Recorder Autoscaling Project

Production-ready Docker-based Jibri recorder autoscaling setup for Jitsi Meet.

This project runs **Jitsi Meet on one VM** and **multiple Jibri recorder containers on a separate Jibri VM**.  
Recorders scale automatically based on **recording availability**, not CPU load, doctor appointments, or general traffic.

---

## 🚀 What This Project Does

- Runs multiple Jibri recorders using Docker Compose.
- Keeps at least **one recorder always ready**.
- Starts a new recorder when all running recorders are busy.
- Stops extra idle recorders after a configured timeout.
- Supports up to **30 Jibri recorder containers**.
- Stores recordings persistently on the Jibri VM using host-mounted volumes.
- Prevents active recordings from being killed by the autoscaler.

---

## 🏗️ Architecture Diagram

```mermaid
flowchart TD
    A[Doctor / User Browser] -->|HTTPS 443| B[Jitsi Web<br/>telemed.pro.e-resourceplanning.com]

    B --> C[Jicofo<br/>Conference Focus]
    C --> D[Prosody XMPP Server]
    C --> E[JVB<br/>Jitsi Videobridge]

    D -->|Jibri Brewery MUC| F[Jibri VM<br/>192.168.223.116]

    F --> G1[Jibri 1<br/>Recorder Container]
    F --> G2[Jibri 2<br/>Recorder Container]
    F --> G3[Jibri 3<br/>Recorder Container]
    F --> G4[Jibri N<br/>Up to 30 Containers]

    G1 -->|Chrome joins meeting| B
    G1 -->|UDP 10000 Media| E
    G2 -->|UDP 10000 Media| E
    G3 -->|UDP 10000 Media| E
    G4 -->|UDP 10000 Media| E

    F --> H[Autoscaler Script<br/>Checks Jibri Health API]
    H -->|No IDLE recorder available| I[Start Next Jibri Container]
    H -->|Extra recorder idle for 10 minutes| J[Stop Extra Idle Container]

    G1 --> K[Host Mounted Recording Storage]
    G2 --> K
    G3 --> K
    G4 --> K

    K --> L[/recordings/jibri1<br/>/recordings/jibri2<br/>/recordings/jibriN]
