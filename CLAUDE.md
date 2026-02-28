# Tidybot Army

Robot control project for a mobile manipulator: a Franka Panda arm mounted on a Tidybot base, running on a mini PC. An AI agent server (`tidybot-agent-server`) provides a unified API to control both the arm and base.

## Project Structure

- `start_robot.sh` — **Simplified startup script** (starts all services, Ctrl+C to stop)
- `tidybot2/` — Tidybot mobile base code, IK solver, teleop, gamepad control, policy server, episode storage
- `franka_interact/` — Franka Panda arm client-server interface (ZMQ-based)
  - ROS-free, 1 kHz control loop
  - Supports rewind (trajectory reversal) and joint unlock
  - **Auto-hold**: Active position holding instead of gravity compensation (see `franka_interact/franka_server/CLAUDE.md`)
  - `franka_server/start_server.sh` — Starts the arm communication server
- `base_server/` — Mobile base RPC server
- `gripper_server/` — Robotiq gripper control server (ZMQ-based)
- `camera_server/` — Intel RealSense camera streaming server (see `camera_server/CLAUDE.md`)
- `mocap_server/` — Motion capture server (OptiTrack Motive via NatNet)
- `tidybot-agent-server/` — FastAPI hardware server for AI agents (see `tidybot-agent-server/CLAUDE.md`)
  - Unified API for arm + base + gripper + mocap commands, cameras
  - Lease system, safety envelope, trajectory recording, reset via reversal
  - Code Execution API with `robot_sdk` (recommended control method)
  - `service_clients/` — Downloaded client SDKs for backend ML services
  - Web dashboard at `/services/dashboard`
- `system_logger/` — Trajectory recording and rewind orchestration
- `backend_wishlist/` — Shared git repo with `wishlist.json` and `catalog.json` for backend ML service requests
- `pick_obj/` — Pick-and-place skill scripts (visual servoing, EE calibration)
- `sync_catalog.sh` — Cron script (every 30 min) that pulls `catalog.json` and downloads service client SDKs

## Quick Start

### Prerequisites

**Set Franka credentials** (add to `~/.bashrc` or run before starting):
```bash
export FRANKA_DESK_USERNAME=your_username
export FRANKA_DESK_PASSWORD=your_password
```

### Running the Robot (Two-Terminal)

Recommended approach for running with hardware. Separates backend services from the API server.

**Terminal 1 — Start robot services:**
```bash
cd ~/tidybot_army
./start_robot.sh --no-controller
```

**Terminal 2 — Start API server:**
```bash
cd ~/tidybot_army/tidybot-agent-server
source ~/tidybot_army/franka_interact/.venv/bin/activate
python3 server.py --no-service-manager
```

The API server is now available at http://localhost:8080

**start_robot.sh options:**
- `--no-unlock` — Skip unlock step (if robot is already unlocked)
- `--no-gripper` — Skip starting the gripper server
- `--no-camera` — Skip starting the camera server
- `--no-controller` — Skip whole-body controller (**always required** — `qp_arm_only.py` no longer exists)
- `--camera-config <path>` — Use a custom camera configuration file (YAML/JSON)

### Development Mode (Single Terminal)

For development without `start_robot.sh`, run the agent server with the service manager enabled:

```bash
cd ~/tidybot_army/tidybot-agent-server
source ~/tidybot_army/franka_interact/.venv/bin/activate
python3 server.py
```

Then start/stop individual services via the dashboard at http://localhost:8080/services/dashboard or via API:

```bash
curl -X POST localhost:8080/services/unlock/start
curl -X POST localhost:8080/services/franka_server/start
curl -X POST localhost:8080/services/gripper_server/start
# etc.
```

This makes it easy to toggle individual services without restarting everything. For dry-run mode (no hardware): `python3 server.py --dry-run`

## Rewind System (Trajectory Reversal)

The rewind system enables error recovery by replaying the robot's trajectory in reverse. It coordinates base and arm movements together using recorded waypoints.

- **Recording:** StateAggregator records unified waypoints at 10 Hz (threshold-filtered)
- **Execution:** RewindOrchestrator groups waypoints into chunks, interpolates arm (cubic) and base (linear + Ruckig) at 50 Hz
- **SDK:** Available in code execution as `from robot_sdk import rewind`
- **API:** Full REST API at `/rewind/*` (see `tidybot-agent-server/CLAUDE.md`)
- **Config:** Tune `chunk_size`, `chunk_duration` online via `PUT /rewind/config`

### Key Files

| File | Description |
|------|-------------|
| `system_logger/system_logger/waypoint.py` | UnifiedWaypoint dataclass |
| `system_logger/system_logger/logger.py` | SystemLogger (trajectory recording) |
| `system_logger/system_logger/rewind_orchestrator.py` | RewindOrchestrator (execution) |
| `system_logger/system_logger/config.py` | LoggerConfig, RewindConfig, WorkspaceBounds |

## Error Recovery

### Robot in Reflex Mode

If the arm enters error state (collision, etc.):

```bash
cd ~/tidybot_army/franka_interact/franka_server
./recover.sh --ip 172.16.0.2
```

Then restart services (Ctrl+C `start_robot.sh` and re-run, or restart via service manager).

### Rewind

Use rewind to replay trajectory backwards and escape collisions:

```bash
LEASE=$(curl -s -X POST localhost:8080/lease/acquire \
  -H "Content-Type: application/json" \
  -d '{"holder": "recovery"}' | jq -r '.lease_id')

curl -X POST localhost:8080/rewind/percentage \
  -H "X-Lease-Id: $LEASE" \
  -H "Content-Type: application/json" \
  -d '{"percentage": 10.0}'
```

## OpenClaw Integration

OpenClaw is an AI agent platform that can control the robot. Integration uses auto-generated documentation endpoints — the agent reads the system guide and SDK reference, then writes direct HTTP calls.

```
OpenClaw Agent → GET /docs/guide + /code/sdk → Writes requests.get()/post() → tidybot-agent-server → Hardware
```

## Virtual Environments

| Path | Purpose |
|------|---------|
| `franka_interact/.venv/` | Franka server, agent server |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `FRANKA_DESK_USERNAME` | Franka Desk login username |
| `FRANKA_DESK_PASSWORD` | Franka Desk login password |
| `FRANKA_IP` | Robot IP (default: 172.16.0.2) |
| `ROBOT_API_KEY` | API key for agent server auth — set to an admin key from `tidybot-agent-server/api_keys.json`. Forwarded to SDK subprocesses. Auth disabled when unset. |

## Ports

| Port | Service | Bind |
|------|---------|------|
| 8080 | Agent server (HTTP/WebSocket) | 0.0.0.0 (public) |
| 50000 | Base server (RPC) | localhost |
| 5555 | Franka server (ZMQ commands) | localhost |
| 5556 | Franka server (ZMQ state) | localhost |
| 5557 | Franka server (ZMQ stream) | localhost |
| 5570 | Gripper server (ZMQ commands) | localhost |
| 5571 | Gripper server (ZMQ state) | localhost |
| 5580 | Camera server (WebSocket) | localhost |
| 5590 | Mocap server (TCP) | localhost |
