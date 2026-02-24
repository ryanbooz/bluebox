"""Scenario registry — decorator, storage, and selection.

Scenario files register themselves by importing and using the @scenario
decorator. The __init__.py auto-discovers all .py files in this package
so no manual registration is needed.
"""

import random
from dataclasses import dataclass
from typing import Callable


@dataclass
class Scenario:
    """A registered load-testing scenario."""
    name: str
    method: str
    route: str
    weight: int
    func: Callable
    category: str = "read"


_scenarios: list[Scenario] = []


def scenario(method: str, route: str, weight: int = 10, category: str = "read"):
    """Decorator to register a function as a load-testing scenario."""
    def decorator(func: Callable) -> Callable:
        _scenarios.append(Scenario(
            name=f"{method} {route}",
            method=method,
            route=route,
            weight=weight,
            func=func,
            category=category,
        ))
        return func
    return decorator


def get_all_scenarios() -> list[Scenario]:
    """Return all registered scenarios."""
    return list(_scenarios)


def pick_scenario() -> Scenario:
    """Select a random scenario based on weights."""
    if not _scenarios:
        raise RuntimeError("No scenarios registered")
    return random.choices(_scenarios, weights=[s.weight for s in _scenarios], k=1)[0]
