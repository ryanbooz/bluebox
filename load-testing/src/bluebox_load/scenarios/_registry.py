"""Scenario registry — decorator, storage, and selection.

Scenario files register themselves by importing and using the @scenario
decorator. The __init__.py auto-discovers all .py files in this package
so no manual registration is needed.

Scenarios can be either weight-based (selected proportionally from the
RPM-driven pool) or interval-based (fired on a fixed cadence independent
of RPM). Use ``weight=`` for realistic app traffic and ``schedule=`` for
infrequent demo/anti-pattern queries.
"""

import re
import random
from dataclasses import dataclass
from typing import Callable

_UNSET = object()  # sentinel to detect explicit weight= in decorator

_INTERVAL_RE = re.compile(
    r"^(?P<lo>\d+)(?:-(?P<hi>\d+))?(?P<unit>[smh])$"
)
_UNIT_SECONDS = {"s": 1, "m": 60, "h": 3600}


def parse_interval(spec: str) -> tuple[float, float]:
    """Parse an interval spec into (min_seconds, max_seconds).

    Examples:
        "4-8h"  -> (14400.0, 28800.0)
        "10-30m" -> (600.0, 1800.0)
        "30m"   -> (1800.0, 1800.0)
    """
    m = _INTERVAL_RE.match(spec)
    if not m:
        raise ValueError(
            f"Invalid interval format '{spec}', "
            "expected e.g. '4-8h', '30m', '10-30m'"
        )
    lo = int(m.group("lo"))
    hi = int(m.group("hi")) if m.group("hi") else lo
    unit = _UNIT_SECONDS[m.group("unit")]
    if hi < lo:
        raise ValueError(
            f"Interval high ({hi}) must be >= low ({lo}) in '{spec}'"
        )
    return (lo * unit, hi * unit)


@dataclass
class Scenario:
    """A registered load-testing scenario."""
    name: str
    method: str
    route: str
    weight: int
    func: Callable
    category: str = "read"
    schedule: str | None = None
    schedule_min_s: float | None = None
    schedule_max_s: float | None = None


_scenarios: list[Scenario] = []


def scenario(
    method: str,
    route: str,
    weight: int = _UNSET,
    category: str = "read",
    schedule: str | None = None,
):
    """Decorator to register a function as a load-testing scenario.

    Use ``weight=N`` for RPM-pool scenarios or ``schedule="4-8h"`` for
    interval-based scenarios.  These are mutually exclusive.
    """
    def decorator(func: Callable) -> Callable:
        effective_weight = weight
        sched_min = sched_max = None

        if schedule is not None:
            if weight is not _UNSET:
                raise ValueError(
                    f"Scenario '{method} {route}': "
                    "cannot set both weight= and schedule="
                )
            effective_weight = 0
            sched_min, sched_max = parse_interval(schedule)
        elif weight is _UNSET:
            effective_weight = 10  # default weight

        _scenarios.append(Scenario(
            name=f"{method} {route}",
            method=method,
            route=route,
            weight=effective_weight,
            func=func,
            category=category,
            schedule=schedule,
            schedule_min_s=sched_min,
            schedule_max_s=sched_max,
        ))
        return func
    return decorator


def get_all_scenarios() -> list[Scenario]:
    """Return all registered scenarios."""
    return list(_scenarios)


def get_weighted_scenarios() -> list[Scenario]:
    """Return scenarios that participate in the RPM-driven weighted pool."""
    return [s for s in _scenarios if s.schedule is None and s.weight > 0]


def get_interval_scenarios() -> list[Scenario]:
    """Return scenarios that run on a fixed interval."""
    return [s for s in _scenarios if s.schedule is not None]


def pick_scenario() -> Scenario:
    """Select a random scenario from the weighted (non-interval) pool."""
    weighted = get_weighted_scenarios()
    if not weighted:
        raise RuntimeError("No weighted scenarios registered")
    return random.choices(
        weighted, weights=[s.weight for s in weighted], k=1
    )[0]
