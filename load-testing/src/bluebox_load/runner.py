"""Load generation runner — manages the dispatch loop and lifecycle.

Uses a single-threaded dispatch model since all work is I/O-bound
database queries. The connection pool handles concurrency at the DB layer.
"""

import logging
import signal
import threading

from .config import Config
from .db import connection
from .scenarios import pick_scenario, get_all_scenarios
from .scheduler import calculate_rpm, rpm_to_delay

log = logging.getLogger(__name__)


class LoadRunner:
    """Manages the load generation lifecycle."""

    def __init__(self, config: Config):
        self.config = config
        self._stop_event = threading.Event()
        self._stats_lock = threading.Lock()
        self._stats = {
            "total": 0,
            "success": 0,
            "error": 0,
            "by_scenario": {},
        }
        self._current_rpm: float = config.base_rpm
        self._current_delay: float = 1.0

    def run(self) -> None:
        """Start the load generation loop. Blocks until stopped."""
        self._install_signal_handlers()

        scenarios = get_all_scenarios()
        log.info("Registered %d scenarios:", len(scenarios))
        total_weight = sum(s.weight for s in scenarios)
        for s in sorted(scenarios, key=lambda x: x.weight, reverse=True):
            pct = (s.weight / total_weight) * 100
            log.info("  %-30s weight=%d (%.1f%%)", s.name, s.weight, pct)

        self._update_rpm()

        # Background threads for RPM updates and stats logging
        rpm_thread = threading.Thread(target=self._rpm_updater, daemon=True, name="rpm-updater")
        rpm_thread.start()

        stats_thread = threading.Thread(target=self._stats_logger, daemon=True, name="stats-logger")
        stats_thread.start()

        log.info("Load generation started (RPM=%.1f, delay=%.2fs)", self._current_rpm, self._current_delay)

        while not self._stop_event.is_set():
            try:
                self._dispatch_one()
            except Exception:
                log.exception("Unexpected error in dispatch loop")

            self._stop_event.wait(timeout=self._current_delay)

        log.info("Load generation stopped")
        self._log_final_stats()

    def stop(self) -> None:
        """Signal the runner to stop."""
        log.info("Stop requested, finishing current work...")
        self._stop_event.set()

    def _dispatch_one(self) -> None:
        """Pick a scenario, borrow a connection, execute it."""
        scenario = pick_scenario()

        try:
            with connection() as conn:
                scenario.func(conn)

            with self._stats_lock:
                self._stats["total"] += 1
                self._stats["success"] += 1
                self._stats["by_scenario"].setdefault(scenario.name, {"success": 0, "error": 0})
                self._stats["by_scenario"][scenario.name]["success"] += 1

        except Exception:
            log.warning("Scenario '%s' failed", scenario.name, exc_info=True)
            with self._stats_lock:
                self._stats["total"] += 1
                self._stats["error"] += 1
                self._stats["by_scenario"].setdefault(scenario.name, {"success": 0, "error": 0})
                self._stats["by_scenario"][scenario.name]["error"] += 1

    def _update_rpm(self) -> None:
        """Recalculate RPM from scheduler."""
        try:
            with connection() as conn:
                self._current_rpm = calculate_rpm(self.config, conn)
                self._current_delay = rpm_to_delay(self._current_rpm)
                log.debug("RPM updated: %.1f (delay=%.2fs)", self._current_rpm, self._current_delay)
        except Exception:
            log.warning("Failed to update RPM, keeping current value", exc_info=True)

    def _rpm_updater(self) -> None:
        """Background thread: recalculate RPM every 60 seconds."""
        while not self._stop_event.is_set():
            self._stop_event.wait(timeout=60.0)
            if not self._stop_event.is_set():
                self._update_rpm()

    def _stats_logger(self) -> None:
        """Background thread: log stats every 60 seconds."""
        while not self._stop_event.is_set():
            self._stop_event.wait(timeout=60.0)
            if not self._stop_event.is_set():
                self._log_stats()

    def _log_stats(self) -> None:
        with self._stats_lock:
            log.info(
                "Stats: total=%d success=%d error=%d rpm=%.1f",
                self._stats["total"],
                self._stats["success"],
                self._stats["error"],
                self._current_rpm,
            )

    def _log_final_stats(self) -> None:
        with self._stats_lock:
            log.info("=" * 55)
            log.info("  Final Statistics")
            log.info("=" * 55)
            log.info("  Total executions: %d", self._stats["total"])
            log.info("  Successes: %d", self._stats["success"])
            log.info("  Errors: %d", self._stats["error"])
            if self._stats["by_scenario"]:
                log.info("  %-30s %8s %8s", "Scenario", "OK", "Err")
                log.info("  %-30s %8s %8s", "-" * 30, "-" * 8, "-" * 8)
                for name, counts in sorted(self._stats["by_scenario"].items()):
                    log.info("  %-30s %8d %8d", name, counts["success"], counts["error"])
            log.info("=" * 55)

    def _install_signal_handlers(self) -> None:
        """Install SIGINT and SIGTERM handlers for graceful shutdown."""
        def handler(signum, frame):
            sig_name = signal.Signals(signum).name
            log.info("Received %s", sig_name)
            self.stop()

        signal.signal(signal.SIGINT, handler)
        signal.signal(signal.SIGTERM, handler)
