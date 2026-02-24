"""Scenario auto-discovery and public API.

Importing this package automatically discovers and loads all scenario
files in this directory. Contributors just need to create a new .py file
with a @scenario-decorated function — no manual registration required.

Public API (re-exported from _registry):
    scenario         — decorator to register a scenario
    get_all_scenarios — return all registered scenarios
    pick_scenario    — weighted random selection
    Scenario         — the scenario dataclass
"""

import importlib
import pkgutil

from ._registry import Scenario, get_all_scenarios, pick_scenario, scenario  # noqa: F401

# Auto-discover all modules in this package to trigger @scenario registration
for _info in pkgutil.iter_modules(__path__):
    if not _info.name.startswith("_"):
        importlib.import_module(f".{_info.name}", __package__)
