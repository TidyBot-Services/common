#!/bin/bash
# Creates symlinks in the parent directory (~/tidybot_uni/) pointing to common/ files.
# Run from anywhere — the script resolves its own location.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARENT="$(dirname "$SCRIPT_DIR")"
REL="common"

for f in logging_config.py start_robot.sh sync_catalog.sh CLAUDE.md; do
    ln -sfn "$REL/$f" "$PARENT/$f"
    echo "  $f → $REL/$f"
done

echo "Done."
