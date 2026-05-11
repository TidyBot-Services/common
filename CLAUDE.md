# Tidybot Universe — Project Instructions

An end-to-end platform that unifies simulation, real hardware, and multi-agent AI into a single autonomous mobile-manipulator development loop.

## 📍 Read this file, then `docs/ai-memory/active-context.md`

**This file stays short.** Project history, decisions, module docs, and lessons live in `docs/ai-memory/` — a structured AI-memory tree separate from this stable rules file.

```
docs/ai-memory/
├── active-context.md       ← read FIRST every session
├── progress.md             ← milestones / known issues
├── project-brief.md        ← what + why + architecture
├── decisions/              ← ADR-style decision records
├── modules/                ← per-module reference
└── patterns/               ← cross-module lessons
```

## Startup Routine

When starting work on this repo:

1. Read this file (rules + commands).
2. Read `docs/ai-memory/active-context.md` (current focus).
3. If touching a specific component → read the relevant `docs/ai-memory/modules/<name>.md`.
4. If asking "why is X this way" → check `docs/ai-memory/decisions/`.

## Memory Policy

- **This file stays short** (target <150 lines). No work logs here.
- **At end of substantial work**, use the closing prompt below to update memory.
- **Decisions are immutable** once shipped; supersede with new ADRs, don't edit old.
- **Personal observations** (model quirks, debugging style preferences) live in private Claude Code memory, not here.

End-of-session prompt:

```
请收尾并更新项目记忆:
1. 更新 docs/ai-memory/active-context.md
2. 完成的 milestone 加进 docs/ai-memory/progress.md
3. 新增重要决策 → docs/ai-memory/decisions/NNNN-<title>.md
4. 个人观察 → 私有 memory(~/.claude/...),不要写进 CLAUDE.md
```

## Engineering Rules

- Preserve the shared SDK abstraction (sim ≡ hardware API surface). See `decisions/0001-shared-hardware-sdk.md`.
- Don't bypass safety, lease, workspace-boundary, reset, or e-stop logic.
- Skills are small, testable, with clear deps. Higher-level skills depend on lower-level interfaces, not internals. See `decisions/0002-skill-dag-decomposition.md`.
- Update tests / validation when changing behavior.
- Push commits atomically when fixes span repos (see `patterns/pathfinder-subdir-shadow.md` for why partial deploys break things).

## Repository Layout

```
agent_server/                 # FastAPI hardware server (lease, code exec, recording)
skill-agent-setup/claude-code/# Orchestrator + harnesses
sims/maniskill/               # ManiSkill server (cuRobo + bridges)
sims/robocasa_tasks/          # RoboCasa task definitions
sims/maniskill_tidyverse/     # Kitchen scene + URDF + cuRobo config
service-agent-setup/          # Deploy-agent daemon (port 9000)
services_wishlist/            # Service catalog + wishlist coordination
hardware/                     # Real-hardware service clients
eval/                         # Evaluation runs, benchmark results
docs/ai-memory/               # ← shared AI memory (this directory)
```

See `docs/ai-memory/project-brief.md` for full architecture and contribution overview.

## Common Commands

### One-time setup
```bash
bash setup.sh <env_name> [<workspace_dir>]
```

### Run sim (ManiSkill, Counter-To-Cab-v0 example)
```bash
cd sims/maniskill
conda run -n maniskill --no-capture-output \
  env LD_PRELOAD=$HOME/miniconda3/envs/maniskill/lib/libstdc++.so.6 \
       DISPLAY=:0 PYTHONUNBUFFERED=1 \
       CUROBO_SERVICE_URL=http://localhost:7000 \
       GRASPGEN_SERVER_URL=http://10.102.245.84:8006 \
       python3 -m maniskill_server --task RoboCasa-Pn-P-Counter-To-Cab-v0 --gui
```

### Run agent server (sim or hw)
```bash
cd agent_server
conda run -n maniskill --no-capture-output \
  env LD_PRELOAD=$HOME/miniconda3/envs/maniskill/lib/libstdc++.so.6 \
       PYTHONUNBUFFERED=1 \
       python3 server.py --no-service-manager
```
API at `http://localhost:8080`.

### Run orchestrator (claude-sdk default)
```bash
cd skill-agent-setup/claude-code
python3 agent_orchestrator.py --graph graphs/<name>
```

### Run orchestrator with openclaw harness
```bash
cd skill-agent-setup/claude-code
~/bin/with-litellm.sh python3 agent_orchestrator.py \
    --graph graphs/<name> --harness openclaw [--autonomous]
```
Setup details: `skill-agent-setup/claude-code/CLAUDE-OPENCLAW-HARNESS.md`.

### Verify deploy-agent pipeline (sanity check)
```bash
bash service-agent-setup/probe_pipeline.sh
```

## Ports (sim + hardware identical)

| Port | Service | Bind |
|------|---------|------|
| 8080 | Agent server | 0.0.0.0 |
| 50000 | Base RPC | localhost |
| 5500 | Sim HTTP API (sim only) | localhost |
| 5555 | Franka ZMQ commands | localhost |
| 5556 | Franka ZMQ state pub | localhost |
| 5557 | Franka ZMQ stream | localhost |
| 5570 | Gripper ZMQ commands | localhost |
| 5571 | Gripper ZMQ state | localhost |
| 5580 | Camera WebSocket | localhost |
| 5590 | Mocap TCP | localhost |
| 7000 | cuRobo service (standalone v0.8) | localhost |
| 8090 | Service catalog (SSH scanner, currently inactive) | localhost |
| 9000 | Deploy-agent daemon | per-host |
| 8765 / 8766 | Orchestrator WebSocket / HTTP | 0.0.0.0 |
| 8070 | Dashboard | 0.0.0.0 |

## Required Environment Variables

| Variable | Description |
|----------|-------------|
| `FRANKA_DESK_USERNAME` / `_PASSWORD` | Franka Desk login (real hardware only) |
| `FRANKA_IP` | Robot IP (default: 172.16.0.2) |
| `ROBOT_API_KEY` | Agent server auth (from `agent_server/api_keys.json`). Auth disabled when unset. |
| `LITELLM_KEY` | Set via `~/bin/with-litellm.sh` from `~/.litellm-key` (chmod 600). Never echo. |
| `CUROBO_SERVICE_URL` | cuRobo standalone service (default: `http://localhost:7000`) |
| `GRASPGEN_SERVER_URL` | Remote GraspGen service (e.g. `http://10.102.245.84:8006`) |

## Related Top-Level Docs

- `README.md` — project README
- `setup.sh` — one-command setup
- `skill-agent-setup/README.md` — agent setup modes (standalone chat vs orchestrator harness)
- `skill-agent-setup/claude-code/CLAUDE.md` — orchestrator-specific dev/planner instructions
- `skill-agent-setup/claude-code/CLAUDE-OPENCLAW-HARNESS.md` — `--harness openclaw` setup walkthrough
- `service-agent-setup/docs/DEPLOY_AGENT_SPEC.md` — deploy-agent API spec
