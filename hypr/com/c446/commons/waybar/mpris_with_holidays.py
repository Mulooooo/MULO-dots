#!/usr/bin/env python3
"""Display MPRIS info with holidays in tooltip"""

import subprocess
import json
from datetime import date, timedelta

try:
    import holidays
except ImportError:
    print("󰎆")
    exit(1)


def get_mpris_status():
    """Get current MPRIS player status via dbus"""
    try:
        result = subprocess.run(
            ["playerctl", "status", "-f", "{{artist}} {{title}}"],
            capture_output=True,
            text=True,
            timeout=1,
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass
    return None


def get_next_holiday_info():
    """Get next French holiday"""
    today = date.today()
    end_date = today + timedelta(days=30)
    fr_holidays = holidays.France(years=[today.year, end_date.year])

    for d, name in sorted(fr_holidays.items()):
        if today < d <= end_date:
            days_until = (d - today).days
            return f"{name} ({days_until}j)"

    return None


def get_calendar_with_holidays():
    """Generate calendar with holidays for tooltip"""
    import calendar

    today = date.today()
    year, month = today.year, today.month

    fr_holidays = holidays.France(years=year)
    cal = calendar.monthcalendar(year, month)

    lines = []
    month_name = calendar.month_name[month]
    lines.append(f"<b>{month_name} {year}</b>")
    lines.append("Mo Tu We Th Fr Sa Su")

    for week in cal:
        week_str = []
        for day in week:
            if day == 0:
                week_str.append("  ")
            else:
                d = date(year, month, day)
                if d in fr_holidays:
                    week_str.append(f"<span color='#FF6188'><b>{day:2d}</b></span>")
                elif d == today:
                    week_str.append(f"<span color='#78DCE8'><u>{day:2d}</u></span>")
                else:
                    week_str.append(f"{day:2d}")
        lines.append(" ".join(week_str))

    lines.append("")
    lines.append("<b>Jours fériés:</b>")
    month_holidays = sorted([
        (d, name) for d, name in fr_holidays.items()
        if d.month == month and d.year == year
    ])

    if month_holidays:
        for d, name in month_holidays:
            lines.append(f"  {d.strftime('%d')}: {name}")
    else:
        lines.append("  Aucun")

    return "\n".join(lines)


if __name__ == "__main__":
    import sys

    mpris = get_mpris_status()
    holiday = get_next_holiday_info()

    # Format for display
    if mpris:
        display = mpris
        if holiday:
            display += f" | {holiday}"
    elif holiday:
        display = holiday
    else:
        display = ""

    print(display)

    # Generate calendar for tooltip (write to temp file that waybar can read)
    if len(sys.argv) > 1 and sys.argv[1] == "--tooltip":
        print(get_calendar_with_holidays())