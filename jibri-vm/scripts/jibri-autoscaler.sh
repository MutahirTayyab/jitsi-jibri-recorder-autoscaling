#!/usr/bin/env bash
set -euo pipefail

WORKDIR="/home/dev-admin/jitsi/jitsi-docker-jitsi-meet-5499476"
COMPOSE_FILE="$WORKDIR/jibri.yml"

MIN_RUNNING=1
MAX_RUNNING=30
IDLE_KEEP_SECONDS=300

STATE_DIR="/var/run/jibri-autoscaler"
mkdir -p "$STATE_DIR"

cd "$WORKDIR"

is_running() {
    local svc="$1"
    local cid
    cid=$(docker compose -f "$COMPOSE_FILE" ps -q "$svc" 2>/dev/null || true)

    if [ -z "$cid" ]; then
        return 1
    fi

    local running
    running=$(docker inspect -f '{{.State.Running}}' "$cid" 2>/dev/null || echo "false")

    [ "$running" = "true" ]
}

start_service() {
    local svc="$1"
    echo "$(date) START $svc"
    docker compose -f "$COMPOSE_FILE" up -d "$svc"
}

stop_service() {
    local svc="$1"
    echo "$(date) STOP $svc"
    docker compose -f "$COMPOSE_FILE" stop "$svc"
}

get_health_json() {
    local port="$1"
    curl -fsS --max-time 4 "http://127.0.0.1:${port}/jibri/api/v1.0/health" 2>/dev/null || true
}

running_count=0
idle_count=0
busy_count=0
starting_count=0

idle_services=()

for i in $(seq 1 "$MAX_RUNNING"); do
    svc="jibri$i"
    port=$((2221+i))

    if is_running "$svc"; then
        running_count=$((running_count + 1))

        json="$(get_health_json "$port")"

        if [ -z "$json" ]; then
            starting_count=$((starting_count + 1))
            rm -f "$STATE_DIR/${svc}.idle_since"
            continue
        fi

        busy_status="$(echo "$json" | jq -r '.status.busyStatus // .busyStatus // "UNKNOWN"')"
        health_status="$(echo "$json" | jq -r '.status.health.healthStatus // .health.healthStatus // .healthStatus // "UNKNOWN"')"

        echo "$(date) $svc health=$health_status busy=$busy_status"

        if [ "$health_status" = "UNHEALTHY" ]; then
            echo "$(date) Restarting unhealthy $svc"
            docker compose -f "$COMPOSE_FILE" restart "$svc"
            rm -f "$STATE_DIR/${svc}.idle_since"
            continue
        fi

        if [ "$busy_status" = "IDLE" ] && [ "$health_status" = "HEALTHY" ]; then
            idle_count=$((idle_count + 1))
            idle_services+=("$svc")

            if [ ! -f "$STATE_DIR/${svc}.idle_since" ]; then
                date +%s > "$STATE_DIR/${svc}.idle_since"
            fi

        elif [ "$busy_status" = "BUSY" ]; then
            busy_count=$((busy_count + 1))
            rm -f "$STATE_DIR/${svc}.idle_since"

        else
            starting_count=$((starting_count + 1))
            rm -f "$STATE_DIR/${svc}.idle_since"
        fi

    else
        rm -f "$STATE_DIR/${svc}.idle_since"
    fi
done

echo "$(date) running=$running_count idle=$idle_count busy=$busy_count starting=$starting_count"

# Keep minimum running.
if [ "$running_count" -lt "$MIN_RUNNING" ]; then
    for i in $(seq 1 "$MAX_RUNNING"); do
        svc="jibri$i"
        if ! is_running "$svc"; then
            start_service "$svc"
            exit 0
        fi
    done
fi

# Scale up if no idle recorder exists.
if [ "$idle_count" -eq 0 ] && [ "$starting_count" -eq 0 ] && [ "$running_count" -lt "$MAX_RUNNING" ]; then
    for i in $(seq 1 "$MAX_RUNNING"); do
        svc="jibri$i"
        if ! is_running "$svc"; then
            start_service "$svc"
            exit 0
        fi
    done
fi

# Scale down:
# keep one idle recorder warm.
if [ "$idle_count" -gt 1 ] && [ "$running_count" -gt "$MIN_RUNNING" ]; then
    now="$(date +%s)"

    for i in $(seq "$MAX_RUNNING" -1 2); do
        svc="jibri$i"

        if printf '%s\n' "${idle_services[@]}" | grep -qx "$svc"; then
            idle_file="$STATE_DIR/${svc}.idle_since"

            if [ -f "$idle_file" ]; then
                idle_since="$(cat "$idle_file")"
                idle_for=$((now - idle_since))

                if [ "$idle_for" -ge "$IDLE_KEEP_SECONDS" ]; then
                    stop_service "$svc"
                    rm -f "$idle_file"
                    exit 0
                fi
            fi
        fi
    done
fi

exit 0
