"""Dates and times print without a leading zero on every OS (Windows' strftime refuses "%-d")."""
import datetime as dt
import pathlib
import re

from apps.common.utils import dfmt


def test_dfmt_drops_leading_zeros():
    assert dfmt(dt.datetime(2026, 10, 6, 8, 5), "%a, %-d %b · %-I:%M %p") == "Tue, 6 Oct · 8:05 AM"
    assert dfmt(dt.time(0, 30), "%-I:%M %p") == "12:30 AM"
    assert dfmt(dt.date(2026, 1, 2), "%-d/%-m") == "2/1"


def test_no_platform_only_strftime_codes_left():
    apps = pathlib.Path(__file__).resolve().parent.parent / "apps"
    bad = [f"{p.relative_to(apps)}:{i}" for p in apps.rglob("*.py") if "migrations" not in p.parts
           for i, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1)
           if re.search(r"(strftime\([^)]*%-|:%[^}]*%-|\{[^}]*:%-)", line) and "dfmt(" not in line]
    assert not bad, bad
