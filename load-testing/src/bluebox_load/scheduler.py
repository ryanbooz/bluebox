"""Time-of-day scheduling and rate calculation.

Determines the target requests-per-minute based on current hour,
day of week, and holidays.
"""

import logging
from datetime import datetime
from zoneinfo import ZoneInfo

import psycopg

from .config import Config

log = logging.getLogger(__name__)

# (start_hour, end_hour, period_name)
HOUR_SCHEDULE: list[tuple[int, int, str]] = [
    (0, 6, "night"),
    (6, 9, "morning"),
    (9, 12, "midday"),
    (12, 14, "lunch"),
    (14, 17, "afternoon"),
    (17, 21, "evening"),
    (21, 24, "late"),
]

DEFAULT_PERIOD_MULTIPLIERS: dict[str, float] = {
    "night": 0.1,
    "morning": 0.5,
    "midday": 0.8,
    "lunch": 1.2,
    "afternoon": 0.7,
    "evening": 2.5,
    "late": 0.6,
}

WEEKEND_MULTIPLIER: float = 1.4


def get_current_period(tz: ZoneInfo) -> str:
    """Return the current period name based on local time."""
    hour = datetime.now(tz).hour
    for start, end, name in HOUR_SCHEDULE:
        if start <= hour < end:
            return name
    return "night"


def is_holiday_today(conn: psycopg.Connection, tz: ZoneInfo) -> bool:
    """Check if today is a holiday by querying the bluebox.holiday table."""
    today = datetime.now(tz).date()
    cur = conn.cursor()
    cur.execute(
        "SELECT EXISTS(SELECT 1 FROM holiday WHERE holiday_date = %s)",
        (today,),
    )
    result = cur.fetchone()[0]
    cur.close()
    return result


def is_weekend(tz: ZoneInfo) -> bool:
    """Check if the current day is Saturday or Sunday."""
    return datetime.now(tz).weekday() >= 5


def calculate_rpm(config: Config, conn: psycopg.Connection) -> float:
    """Calculate the target requests per minute for the current moment.

    Combines base_rpm with time-of-day, weekend, and holiday multipliers.
    """
    tz = ZoneInfo(config.timezone)
    period = get_current_period(tz)

    # Start with default multiplier, then apply config overrides
    multiplier = DEFAULT_PERIOD_MULTIPLIERS.get(period, 1.0)
    if period == "night":
        multiplier = config.night_multiplier
    elif period == "evening":
        multiplier = config.evening_multiplier

    rpm = config.base_rpm * multiplier

    if is_weekend(tz):
        rpm *= WEEKEND_MULTIPLIER

    if is_holiday_today(conn, tz):
        rpm *= config.holiday_multiplier
        log.debug("Holiday detected, applying %.1fx multiplier", config.holiday_multiplier)

    log.debug("Period=%s, RPM=%.1f (base=%d, mult=%.2f)", period, rpm, config.base_rpm, multiplier)
    return rpm


def rpm_to_delay(rpm: float) -> float:
    """Convert requests-per-minute to delay in seconds between requests.

    Returns minimum 0.1 seconds to prevent CPU spinning.
    """
    if rpm <= 0:
        return 60.0
    return max(0.1, 60.0 / rpm)
