#!/usr/bin/env python3
"""Display French holidays in waybar, integrated with clock calendar"""

import calendar
from datetime import date, timedelta
try:
    import holidays
except ImportError:
    print("Error: install holidays library")
    exit(1)


def get_todays_holiday(test_date=None):
    """Return holiday name if today is a French holiday, else None"""
    today = test_date or date.today()
    fr_holidays = holidays.France(years=today.year)
    return fr_holidays.get(today)


def get_next_holiday(test_date=None, days_ahead=30):
    """Find the next French holiday within days_ahead"""
    start_date = test_date or date.today()
    end_date = start_date + timedelta(days=days_ahead)

    fr_holidays = holidays.France(years=[start_date.year, end_date.year])

    for d, name in sorted(fr_holidays.items()):
        if start_date < d <= end_date:
            return (d.strftime("%Y-%m-%d"), name)

    return None


def format_holiday_display(todays_holiday=None, next_holiday=None):
    """Format holiday info for waybar status bar"""
    if todays_holiday:
        return f"🎉 {todays_holiday}"

    if next_holiday:
        date_str, holiday_name = next_holiday
        days_until = (
            date.fromisoformat(date_str) - date.today()
        ).days
        return f"{holiday_name} ({days_until}j)"

    return ""


def get_calendar_with_holidays(year=None, month=None):
    """Generate calendar with French holidays highlighted for tooltip"""
    if year is None:
        year = date.today().year
    if month is None:
        month = date.today().month

    today = date.today()
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
                    # Holiday - red bold
                    week_str.append(f"<span color='#FF6188'><b>{day:2d}</b></span>")
                elif d == today:
                    # Today - cyan underline
                    week_str.append(f"<span color='#78DCE8'><u>{day:2d}</u></span>")
                else:
                    week_str.append(f"{day:2d}")
        lines.append(" ".join(week_str))

    # Add holidays list
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

    if len(sys.argv) > 1 and sys.argv[1] == "--calendar":
        # Output full calendar (for tooltip)
        print(get_calendar_with_holidays())
    else:
        # Output status (for main display)
        todays = get_todays_holiday()
        next_h = get_next_holiday()
        main_text = format_holiday_display(todays, next_h)
        print(main_text)