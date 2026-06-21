#!/usr/bin/env python3
"""Tests for French holiday display in waybar"""

import unittest
from datetime import date, timedelta
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
from show_holidays import get_todays_holiday, get_next_holiday, format_holiday_display


class TestFrenchHolidays(unittest.TestCase):
    """Test holiday display functions"""

    def test_get_todays_holiday_on_labor_day(self):
        """Labor Day (May 1) should return the holiday name"""
        result = get_todays_holiday(test_date=date(2026, 5, 1))
        self.assertEqual(result, "Fête du Travail")

    def test_get_todays_holiday_on_regular_day(self):
        """Regular day should return None"""
        result = get_todays_holiday(test_date=date(2026, 5, 18))
        self.assertIsNone(result)

    def test_get_next_holiday_finds_labor_day(self):
        """Should find Fête du Travail (May 1) from April 30"""
        result = get_next_holiday(test_date=date(2026, 4, 30), days_ahead=365)
        self.assertIsNotNone(result)
        self.assertIn("Fête du Travail", result[1])

    def test_format_holiday_with_today(self):
        """Format should show holiday when it's today"""
        result = format_holiday_display(todays_holiday="Fête du Travail")
        self.assertIn("Fête du Travail", result)
        self.assertNotIn("🇫🇷", result)

    def test_format_holiday_with_next(self):
        """Format should show next holiday when not today"""
        result = format_holiday_display(next_holiday=("2026-05-01", "Fête du Travail"))
        self.assertIn("Fête du Travail", result)

    def test_format_holiday_empty(self):
        """Format should handle no holidays gracefully"""
        result = format_holiday_display()
        self.assertEqual(result, "")


if __name__ == "__main__":
    unittest.main()