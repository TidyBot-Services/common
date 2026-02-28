#!/bin/bash
#
# Start all robot services: unlock, base_server, gripper_server, camera_server, franka_server, controller
# Usage: ./start_robot.sh [--no-unlock] [--no-controller] [--no-gripper] [--no-camera] [--camera-config <path>]
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

# Parse arguments
NO_CONTROLLER=false
NO_UNLOCK=false
NO_GRIPPER=false
NO_CAMERA=false
CAMERA_CONFIG=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-controller)
            NO_CONTROLLER=true
            shift
            ;;
        --no-unlock)
            NO_UNLOCK=true
            shift
            ;;
        --no-gripper)
            NO_GRIPPER=true
            shift
            ;;
        --no-camera)
            NO_CAMERA=true
            shift
            ;;
        --camera-config)
            CAMERA_CONFIG="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# Kill a process and all its children
kill_tree() {
    local pid=$1
    local name=$2
    if [ -n "$pid" ]; then
        info "Stopping $name (PID $pid)..."
        # Kill all children first, then the parent
        pkill -TERM -P $pid 2>/dev/null || true
        kill -TERM $pid 2>/dev/null || true
        # Give it a moment, then force kill if still running
        sleep 0.5
        pkill -KILL -P $pid 2>/dev/null || true
        kill -KILL $pid 2>/dev/null || true
    fi
}

# Cleanup function
cleanup() {
    echo ""
    info "Shutting down..."

    # Disable the trap to prevent re-entry
    trap - INT TERM

    # Kill processes in reverse order (dependents first)
    kill_tree "$CONTROLLER_PID" "controller"
    kill_tree "$FRANKA_PID" "franka_server"
    kill_tree "$CAMERA_PID" "camera_server"
    kill_tree "$GRIPPER_PID" "gripper_server"
    kill_tree "$BASE_PID" "base_server"
    kill_tree "$UNLOCK_PID" "unlock"

    # Wait for processes to fully terminate
    sleep 1

    # Lock the robot, no longer needed
    # info "Locking robot..."
    # cd "$SCRIPT_DIR/franka_interact/franka_server"
    # source "$SCRIPT_DIR/franka_interact/.venv/bin/activate"
    # ./lock_unlock.sh --lock 2>/dev/null || true

    info "Shutdown complete"
    exit 0
}

trap cleanup INT TERM

echo ""
echo "=========================================="
echo "  TidyBot Robot Launcher"
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

# 1. Unlock robot and activate FCI (optional)
if [ "$NO_UNLOCK" = false ]; then
    info "Unlocking robot and activating FCI..."
    cd "$SCRIPT_DIR/franka_interact/franka_server"
    source "$SCRIPT_DIR/franka_interact/.venv/bin/activate"
    ./lock_unlock.sh --unlock --fci --persistent --wait &
    UNLOCK_PID=$!
    info "Unlock process started (PID $UNLOCK_PID)"
    sleep 15
else
    info "Skipping unlock (--no-unlock)"
fi

# 2. Start base server
info "Starting base server..."
cd "$SCRIPT_DIR/base_server"
python3 -m base_server.server &
BASE_PID=$!
info "Base server started (PID $BASE_PID)"
sleep 2

# 3. Start gripper server (optional)
if [ "$NO_GRIPPER" = false ]; then
    info "Starting gripper server..."
    cd "$SCRIPT_DIR/gripper_server"
    source "$SCRIPT_DIR/franka_interact/.venv/bin/activate"
    python -m gripper_server.server &
    GRIPPER_PID=$!
    info "Gripper server started (PID $GRIPPER_PID)"
    sleep 2
else
    info "Skipping gripper server (--no-gripper)"
fi

# 4. Start camera server (optional)
if [ "$NO_CAMERA" = false ]; then
    info "Starting camera server..."
    cd "$SCRIPT_DIR/camera_server"
    source "$SCRIPT_DIR/franka_interact/.venv/bin/activate"
    if [ -n "$CAMERA_CONFIG" ]; then
        # Convert to absolute path if relative
        if [[ "$CAMERA_CONFIG" != /* ]]; then
            CAMERA_CONFIG="$SCRIPT_DIR/$CAMERA_CONFIG"
        fi
        python -m camera_server.server --config "$CAMERA_CONFIG" &
    elif [ -f "$SCRIPT_DIR/camera_server/cameras.yaml" ]; then
        python -m camera_server.server --config "$SCRIPT_DIR/camera_server/cameras.yaml" &
    else
        python -m camera_server.server &
    fi
    CAMERA_PID=$!
    info "Camera server started (PID $CAMERA_PID)"
    sleep 2
else
    info "Skipping camera server (--no-camera)"
fi

# 5. Start franka server
info "Starting franka server..."
cd "$SCRIPT_DIR/franka_interact/franka_server"
source "$SCRIPT_DIR/franka_interact/.venv/bin/activate"
./start_server.sh &
FRANKA_PID=$!
info "Franka server started (PID $FRANKA_PID)"
sleep 3

# 6. Start controller (optional)
if [ "$NO_CONTROLLER" = false ]; then
    info "Starting whole-body controller..."
    cd "$SCRIPT_DIR/tidybot2"
    source "$SCRIPT_DIR/franka_interact/.venv/bin/activate"
    python3 -u qp_arm_only.py &
    CONTROLLER_PID=$!
    info "Controller started (PID $CONTROLLER_PID)"
fi

echo ""
info "All services started!"
echo ""
if [ -n "$UNLOCK_PID" ]; then
    echo "  Unlock:         PID $UNLOCK_PID"
fi
echo "  Base Server:    PID $BASE_PID"
if [ -n "$GRIPPER_PID" ]; then
    echo "  Gripper Server: PID $GRIPPER_PID"
fi
if [ -n "$CAMERA_PID" ]; then
    echo "  Camera Server:  PID $CAMERA_PID"
fi
echo "  Franka Server:  PID $FRANKA_PID"
if [ "$NO_CONTROLLER" = false ]; then
    echo "  Controller:     PID $CONTROLLER_PID"
fi
echo ""
info "Press Ctrl+C to stop all services"
echo ""

# Wait for any child to exit
wait
