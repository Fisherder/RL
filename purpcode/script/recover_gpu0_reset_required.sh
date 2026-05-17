#!/usr/bin/env bash
# Recover a GPU that NVIDIA reports as "GPU requires reset" after a hard
# NCCL/CUDA failure. Run this from a real shell with sudo.

set -euo pipefail

GPU_INDEX=${GPU_INDEX:-0}
BUS_ID=${BUS_BUS_ID:-${BUS_ID:-0000:01:00.0}}
STOP_GUI=${STOP_GUI:-0}
REMOVE_RESCAN=${REMOVE_RESCAN:-0}

log() {
    printf '[recover-gpu] %s\n' "$*"
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script needs root privileges for PCI reset."
        echo "Run:"
        echo "  sudo GPU_INDEX=$GPU_INDEX BUS_ID=$BUS_ID bash $0"
        exit 1
    fi
}

show_gpu_state() {
    log "nvidia-smi summary"
    nvidia-smi --query-gpu=index,name,uuid,pci.bus_id,utilization.gpu,memory.used,memory.total,pstate \
        --format=csv,noheader || true
    log "GPU $GPU_INDEX detail"
    nvidia-smi -q -i "$GPU_INDEX" | grep -E "Product Brand|GPU Recovery Action|Bus Id|Used|Free|Processes" || true
}

kill_matching_processes() {
    local pattern=$1
    local label=$2
    local pids
    pids=$(pgrep -f "$pattern" || true)
    if [ -z "$pids" ]; then
        log "no $label processes found"
        return
    fi

    log "terminating $label processes: $pids"
    kill -TERM $pids 2>/dev/null || true
    sleep 3
    pids=$(pgrep -f "$pattern" || true)
    if [ -n "$pids" ]; then
        log "force killing $label processes: $pids"
        kill -KILL $pids 2>/dev/null || true
        sleep 3
    fi
}

stop_gui_if_requested() {
    if [ "$STOP_GUI" = "1" ]; then
        log "stopping graphical target because STOP_GUI=1"
        systemctl isolate multi-user.target || true
        sleep 5
    else
        log "leaving graphical target running; set STOP_GUI=1 if reset is blocked by Xorg/gnome"
    fi
}

restore_gui_if_requested() {
    if [ "$STOP_GUI" = "1" ]; then
        log "restoring graphical target"
        systemctl isolate graphical.target || true
    fi
}

gpu_requires_reset() {
    nvidia-smi -q -i "$GPU_INDEX" 2>/dev/null | grep -q "GPU requires reset"
}

try_nvidia_smi_reset() {
    log "trying nvidia-smi --gpu-reset -i $GPU_INDEX"
    if nvidia-smi --gpu-reset -i "$GPU_INDEX"; then
        return 0
    fi
    log "nvidia-smi reset failed or is unsupported on this GPU"
    return 1
}

try_sysfs_reset() {
    local reset_path="/sys/bus/pci/devices/$BUS_ID/reset"
    if [ ! -e "$reset_path" ]; then
        log "missing sysfs reset path: $reset_path"
        return 1
    fi

    log "trying PCI sysfs reset on $BUS_ID"
    echo 1 > "$reset_path"
    sleep 8
}

try_remove_rescan() {
    if [ "$REMOVE_RESCAN" != "1" ]; then
        log "skip PCI remove/rescan; set REMOVE_RESCAN=1 to allow it"
        return 1
    fi

    local device_dir="/sys/bus/pci/devices/$BUS_ID"
    if [ ! -e "$device_dir/remove" ]; then
        log "missing PCI remove path: $device_dir/remove"
        return 1
    fi

    log "trying PCI remove/rescan on $BUS_ID"
    echo 1 > "$device_dir/remove"
    sleep 5
    echo 1 > /sys/bus/pci/rescan
    sleep 10
}

main() {
    require_root

    log "target GPU_INDEX=$GPU_INDEX BUS_ID=$BUS_ID"
    show_gpu_state

    kill_matching_processes "nvidia-smi -l" "nvidia-smi monitor"
    kill_matching_processes "ray::WorkerDict.actor_rollout_generate_sequences" "orphan Ray rollout worker"

    stop_gui_if_requested
    trap restore_gui_if_requested EXIT

    try_nvidia_smi_reset || true
    if gpu_requires_reset; then
        try_sysfs_reset || true
    fi
    if gpu_requires_reset; then
        try_remove_rescan || true
    fi

    show_gpu_state
    if gpu_requires_reset; then
        log "GPU still requires reset. If REMOVE_RESCAN=1 did not help, reboot is the remaining reliable recovery."
        exit 2
    fi

    log "GPU recovery completed"
}

main "$@"
