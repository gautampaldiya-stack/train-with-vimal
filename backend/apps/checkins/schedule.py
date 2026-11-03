"""When a client's weekly check-in is due, and how long it stays open (Probid 2026-11-03, WORK-TRACKER E23/E28).

- The due day and time come from the client's weekly schedule: an active "Every week" FormSchedule of a weekly
  form (Client profile → Send a form → When). With none, every Sunday at 6:00 pm.
- It can be filled only from its due day, and stays open for OPEN_DAYS more days (reminders at 10 am, 2 pm and
  7 pm each of those days). After that it is Missed and the next one is shown.
- A weekly check-in is stored on its due date, so the week it belongs to never depends on the day it was sent.
- Weight and body measurements are due with it (E29): same day.
"""
from datetime import datetime, time, timedelta

from django.utils import timezone

DEFAULT_WEEKDAY = 6  # Sunday
DEFAULT_TIME = time(18, 0)
OPEN_DAYS = 2  # open on the due day and the 2 days after it
REMIND_HOURS = (10, 14, 19)


def slot(client):
    """(weekday 0 = Monday … 6 = Sunday, time) of this client's weekly check-in."""
    from .models import FormSchedule

    s = (FormSchedule.objects.filter(client=client, form__type="weekly", repeat=FormSchedule.Repeat.WEEK, active=True)
         .order_by("-created_at").only("weekday", "time").first()) if client is not None else None
    if s is None:
        return DEFAULT_WEEKDAY, DEFAULT_TIME
    t = s.time if isinstance(s.time, time) else time.fromisoformat(str(s.time))
    return s.weekday, t


def due_on_or_after(client, day, weekday=None):
    wd = slot(client)[0] if weekday is None else weekday
    return day + timedelta(days=(wd - day.weekday()) % 7)


def due_at(client, due, t=None):
    return timezone.make_aware(datetime.combine(due, t or slot(client)[1]))


def due_for(client, day, weekday=None):
    """The due date a check-in sent on `day` belongs to: the one whose open window holds `day`, else the next one
    (older app builds sent it early)."""
    return due_on_or_after(client, day - timedelta(days=OPEN_DAYS), weekday)


def current(client, today=None):
    """{due, due_at, closes, open, late}: the check-in to show now. The open one when today is inside a window,
    else the next one (locked until its day)."""
    today = today or timezone.localdate()
    wd, t = slot(client)
    due = due_for(client, today, wd)
    if due > today:  # not open yet: the next one
        is_open = False
    else:
        is_open = today <= due + timedelta(days=OPEN_DAYS)
    return {"due": due, "due_at": due_at(client, due, t), "closes": due + timedelta(days=OPEN_DAYS),
            "open": is_open, "late": is_open and today > due, "weekday": wd, "time": t}


def label(client):
    """"every Sunday, 6:00 pm" for the coach's pages."""
    wd, t = slot(client)
    day = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][wd]
    return f"every {day}, {t.strftime('%I:%M %p').lstrip('0').lower().replace(':00', ':00')}"
