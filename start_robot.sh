#!/bin/bash
#
# Start all robot services for the active profile.
#
# Default profile ("full") starts: unlock, base_server, gripper_server,
# camera_server, franka_server, controller — i.e. the Tidybot configuration.
#
# Profile "single_arm_fr3" starts only: unlock, franka_server (FR3 version),
# and optionally gripper_server / camera_server. No mobile base, no controller.
#
# Usage:
#   ./start_robot.sh [--profile <name>] [--no-unlock] [--no-controller]
#                    [--no-gripper] [--no-camera] [--no-base]
#                    [--camera-config <path>]
#
# Examples:
#   ./start_robot.sh                                       # full Tidybot
#   ./start_robot.sh --profile single_arm_fr3              # FR3 workstation
#   ./start_robot.sh --profile single_arm_fr3 --no-gripper # FR3 arm only
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# -----------------------------------------------------------------------------
# Profile + per-component flags
# -----------------------------------------------------------------------------
# Profile sets the *defaults* for what to start; individual --no-X flags can
# override. CLI flag values take precedence over profile defaults.

PROFILE="full"
NO_CONTROLLER_CLI=""
NO_UNLOCK_CLI=""
NO_GRIPPER_CLI=""
NO_CAMERA_CLI=""
NO_BASE_CLI=""
CAMERA_CONFIG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --profile)            PROFILE="$2"; shift 2 ;;
        --no-controller)      NO_CONTROLLER_CLI=true; shift ;;
        --no-unlock)          NO_UNLOCK_CLI=true; shift ;;
        --no-gripper)         NO_GRIPPER_CLI=true; shift ;;
        --no-camera)          NO_CAMERA_CLI=true; shift ;;
        --no-base)            NO_BASE_CLI=true; shift ;;
        --camera-config)      CAMERA_CONFIG="$2"; shift 2 ;;
        -h|--help)
            grep -E '^# ?' "$0" | sed 's/^# \?//' | head -25
            exit 0
            ;;
        *)
            warn "Unknown argument: $1"
            shift
            ;;
    esac
done

# Apply profile defaults. Single-arm profiles disable base + controller by
# default; full Tidybot enables everything. CLI flags still override below.
case "$PROFILE" in
    full|tidybot)
        : "${NO_BASE_DEFAULT:=false}"
        : "${NO_CONTROLLER_DEFAULT:=false}"
        ARM_SERVICE_DIR="$SCRIPT_DIR/arm_franka_service"
        ;;
    single_arm_fr3)
        : "${NO_BASE_DEFAULT:=true}"
        : "${NO_CONTROLLER_DEFAULT:=true}"
        ARM_SERVICE_DIR="$SCRIPT_DIR/arm_franka_fr3_service"
        ;;
    *)
        error "Unknown profile: $PROFILE"
        echo "Available profiles: full, single_arm_fr3"
        exit 1
        ;;
esac

# Final flag values: CLI override > profile default
NO_BASE="${NO_BASE_CLI:-$NO_BASE_DEFAULT}"
NO_CONTROLLER="${NO_CONTROLLER_CLI:-$NO_CONTROLLER_DEFAULT}"
NO_UNLOCK="${NO_UNLOCK_CLI:-false}"
NO_GRIPPER="${NO_GRIPPER_CLI:-false}"
NO_CAMERA="${NO_CAMERA_CLI:-false}"

# Sanity check: chosen arm service must exist (FR3 service may not be set up yet)
if [ ! -d "$ARM_SERVICE_DIR" ]; then
    error "Arm service directory not found: $ARM_SERVICE_DIR"
    error "For profile=$PROFILE you need to set this up first."
    if [ "$PROFILE" = "single_arm_fr3" ]; then
        error "Run: cd $ARM_SERVICE_DIR && ./setup_server.sh"
    fi
    exit 1
fi

# -----------------------------------------------------------------------------
# Process control + cleanup
# -----------------------------------------------------------------------------

kill_tree() {
    local pid=$1
    local name=$2
    if [ -n "$pid" ]; then
        info "Stopping $name (PID $pid)..."
        pkill -TERM -P $pid 2>/dev/null || true
        kill -TERM $pid 2>/dev/null || true
        sleep 0.5
        pkill -KILL -P $pid 2>/dev/null || true
        kill -KILL $pid 2>/dev/null || true
    fi
}

cleanup() {
    echo ""
    info "Shutting down..."
    trap - INT TERM

    kill_tree "$CONTROLLER_PID" "controller"
    kill_tree "$FRANKA_PID" "franka_server"
    kill_tree "$CAMERA_PID" "camera_server"
    kill_tree "$GRIPPER_PID" "gripper_server"
    kill_tree "$BASE_PID" "base_server"
    kill_tree "$UNLOCK_PID" "unlock"

    sleep 1
    info "Shutdown complete"
    exit 0
}

trap cleanup INT TERM

echo ""
echo "=========================================="
echo "  TidyBot Robot Launcher — profile=$PROFILE"
echo "=========================================="
echo ""

# Check for Franka credentials
if [ -z "$FRANKA_DESK_USERNAME" ] || [ -z "$FRANKA_DESK_PASSWORD" ]; then
    error "FRANKA_DESK_USERNAME and FRANKA_DESK_PASSWORD must be set"
    echo "Add to ~/.bashrc:"
    echo "  export FRANKA_DESK_USERNAME='your_username'"
    echo "  export FRANKA_DESK_PASSWORD='your_password'"
    exit 1
fi

# -----------------------------------------------------------------------------
# Bring up services
# -----------------------------------------------------------------------------

# 1. Unlock robot and activate FCI (optional). Uses the lock_unlock.sh script
#    that ships with the chosen arm service.
if [ "$NO_UNLOCK" = false ]; then
    info "Unlocking robot and activating FCI..."
    cd "$ARM_SERVICE_DIR/franka_server"
    ./lock_unlock.sh --unlock --fci --persistent --wait &
    UNLOCK_PID=$!
    info "Unlock process started (PID $UNLOCK_PID)"
    sleep 15
else
    info "Skipping unlock (--no-unlock)"
fi

# 2. Start base server (skipped for single-arm profiles)
if [ "$NO_BASE" = false ]; then
    info "Starting base server..."
    cd "$SCRIPT_DIR/hardware/base_server"
    python3 -m base_server.server &
    BASE_PID=$!
    info "Base server started (PID $BASE_PID)"
    sleep 2
else
    info "Skipping base server (profile=$PROFILE or --no-base)"
fi

# 3. Start gripper server (optional)
if [ "$NO_GRIPPER" = false ]; then
    info "Starting gripper server..."
    cd "$SCRIPT_DIR/hardware/gripper_server"
    python3 -m gripper_server.server &
    GRIPPER_PID=$!
    info "Gripper server started (PID $GRIPPER_PID)"
    sleep 2
else
    info "Skipping gripper server (--no-gripper)"
fi

# 4. Start camera server (optional)
if [ "$NO_CAMERA" = false ]; then
    info "Starting camera server..."
    cd "$SCRIPT_DIR/hardware/camera_server"
    if [ -n "$CAMERA_CONFIG" ]; then
        if [[ "$CAMERA_CONFIG" != /* ]]; then
            CAMERA_CONFIG="$SCRIPT_DIR/$CAMERA_CONFIG"
        fi
        python3 -m camera_server.server --config "$CAMERA_CONFIG" &
    elif [ -f "$SCRIPT_DIR/hardware/camera_server/cameras.yaml" ]; then
        python3 -m camera_server.server --config "$SCRIPT_DIR/hardware/camera_server/cameras.yaml" &
    else
        python3 -m camera_server.server &
    fi
    CAMERA_PID=$!
    info "Camera server started (PID $CAMERA_PID)"
    sleep 2
else
    info "Skipping camera server (--no-camera)"
fi

# 5. Start franka server (always; uses the arm service for the active profile)
info "Starting franka server ($ARM_SERVICE_DIR)..."
cd "$ARM_SERVICE_DIR/franka_server"
./start_server.sh &
FRANKA_PID=$!
info "Franka server started (PID $FRANKA_PID)"
sleep 3

# 6. Start whole-body controller (skipped for single-arm profiles)
if [ "$NO_CONTROLLER" = false ]; then
    info "Starting whole-body controller..."
    cd "$SCRIPT_DIR/tidybot2"
    python3 -u qp_arm_only.py &
    CONTROLLER_PID=$!
    info "Controller started (PID $CONTROLLER_PID)"
else
    info "Skipping controller (profile=$PROFILE or --no-controller)"
fi

echo ""
info "All services started for profile=$PROFILE"
echo ""
if [ -n "$UNLOCK_PID" ];      then echo "  Unlock:         PID $UNLOCK_PID"; fi
if [ -n "$BASE_PID" ];        then echo "  Base Server:    PID $BASE_PID"; fi
if [ -n "$GRIPPER_PID" ];     then echo "  Gripper Server: PID $GRIPPER_PID"; fi
if [ -n "$CAMERA_PID" ];      then echo "  Camera Server:  PID $CAMERA_PID"; fi
echo "  Franka Server:  PID $FRANKA_PID  ($ARM_SERVICE_DIR)"
if [ -n "$CONTROLLER_PID" ];  then echo "  Controller:     PID $CONTROLLER_PID"; fi
echo ""
echo "Tip: launch the agent server with the matching profile, e.g.:"
echo "  cd agent_server && python3 server.py --profile $PROFILE --no-service-manager"
echo ""
info "Press Ctrl+C to stop all services"
echo ""

wait
