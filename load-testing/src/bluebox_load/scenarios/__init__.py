"""Scenario auto-discovery and public API.

Importing this package automatically discovers and loads all scenario
files in this directory. Contributors just need to create a new .py file
with a @scenario-decorated function — no manual registration required.

Public API (re-exported from _registry):
    scenario               — decorator to register a scenario
    get_all_scenarios      — return all registered scenarios
    get_weighted_scenarios — return RPM-pool scenarios only
    get_interval_scenarios — return interval-based scenarios only
    pick_scenario          — weighted random selection
    Scenario               — the scenario dataclass
"""

import importlib
import pkgutil

from ._registry import (  # noqa: F401
    Scenario,
    get_all_scenarios,
    get_weighted_scenarios,
    get_interval_scenarios,
    pick_scenario,
    scenario,
)

# Auto-discover all modules in this package to trigger @scenario registration
for _info in pkgutil.iter_modules(__path__):
    if not _info.name.startswith("_"):
        importlib.import_module(f".{_info.name}", __package__)
