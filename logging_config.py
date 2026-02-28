"""Shared logging configuration for all TidyBot Army components.

Each server entry point calls setup_logging("component_name") at startup.
Library modules just use logging.getLogger(__name__) and inherit handlers.

Log files are written to ~/tidybot_army/logs/ with daily rotation (30 days).
"""

import logging
import os
from collections import deque
from datetime import datetime
from logging.handlers import TimedRotatingFileHandler

LOG_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs")

# Global in-memory log buffer for dashboard display
_log_buffer = None


class LogBuffer(logging.Handler):
    """Captures log records in a ring buffer for dashboard display."""

    def __init__(self, max_entries: int = 200):
        super().__init__()
        self.max_entries = max_entries
        self._buffer = deque(maxlen=max_entries)
        self.setLevel(logging.INFO)

    def emit(self, record):
        try:
            self._buffer.append({
                "timestamp": datetime.now().isoformat(),
                "level": record.levelname,
                "name": record.name,
                "message": record.getMessage(),
            })
        except Exception:
            pass

    def get_logs(self, limit: int = 50):
        entries = list(self._buffer)
        return entries[-limit:]


def get_log_buffer():
    """Get the global log buffer (None if setup_logging hasn't been called)."""
    return _log_buffer


def setup_logging(name: str, level: int = logging.INFO, backup_count: int = 30) -> logging.Logger:
    """Set up logging with console output and daily rotating file handler.

    Args:
        name: Component name, used for the log filename (e.g. "franka_server").
        level: Logging level (default INFO).
        backup_count: Number of daily log files to keep (default 30).

    Returns:
        A logger for the given name.
    """
    os.makedirs(LOG_DIR, exist_ok=True)

    fmt = logging.Formatter("%(asctime)s %(levelname)s %(name)s: %(message)s")

    root = logging.getLogger()
    root.setLevel(level)

    # Console handler (stdout)
    console = logging.StreamHandler()
    console.setFormatter(fmt)
    root.addHandler(console)

    # Daily rotating file handler
    fh = TimedRotatingFileHandler(
        os.path.join(LOG_DIR, f"{name}.log"),
        when="midnight",
        backupCount=backup_count,
    )
    fh.suffix = "%Y-%m-%d"
    fh.setFormatter(fmt)
    root.addHandler(fh)

    # In-memory buffer for dashboard display
    global _log_buffer
    if _log_buffer is None:
        _log_buffer = LogBuffer()
        root.addHandler(_log_buffer)

    return logging.getLogger(name)
