"""Trainer dashboard (boards TrainerDashboard / TrainerDashboardMobile): everything the page shows, in the
words it shows them, so the app only lays it out."""
from datetime import timedelta

from django.db.models import Q
from django.utils import timezone

from apps.accounts.models import AccountStatus
from apps.clients.metrics import active_meal_plan, active_program, planned_workout_days
from apps.common.utils import dfmt


def _person(u):
    return {"id": str(u.id), "name": u.full_name, "initials": u.initials, "color": u.avatar_color}


def _greeting(user, now):
    h = timezone.localtime(now).hour
    part = "morning" if h < 12 else ("afternoon" if h < 17 else "evening")
    return f"Good {part}, {user.first_name}"


def _hours(h):
    """1.4 → '1.4 h', 12 → '12 h'."""
    if h is None:
        return "—"
    return f"{h:.1f} h" if h < 10 else f"{round(h)} h"


def _age(hours):
    """Check-in age chip: '6 h', '2 d'."""
    return f"{max(1, round(hours))} h" if hours < 24 else f"{int(hours // 24)} d"


def _reply_hours(qs):
    hrs = [(s.reviewed_at - s.created_at).total_seconds() / 3600 for s in qs.only("reviewed_at", "created_at")[:1000]]
    return sum(hrs) / len(hrs) if hrs else None


def _range(a, b):
    """'Mon 5 – Thu 8 Oct' (month once when both days share it)."""
    if a.month == b.month:
        return f"{a:%a} {a.day} – {b:%a} {b.day} {b:%b}"
    return f"{a:%a} {a.day} {a:%b} – {b:%a} {b.day} {b:%b}"


KIND_LABEL = {"weekly": "Weekly check-in", "daily": "Daily check-in", "survey": "Monthly progress"}


def stats(user, now, waiting):
    from apps.checkins.models import Submission
    from apps.clients.models import ClientProfile

    tp = user.trainer_profile
    mine = ClientProfile.objects.filter(trainer=user, removed_at__isnull=True, user__status=AccountStatus.ACTIVE)
    n = mine.count()
    over = sum(1 for s in waiting if (now - s.created_at).total_seconds() >= 48 * 3600)
    # Workouts done = share of planned workouts done in the last 7 days, against the 7 days before.
    from apps.training.models import WorkoutLog

    today = timezone.localdate(now)
    end = today - timedelta(days=1)

    def pct(a, b):
        planned = done = 0
        for cp in mine.select_related("user"):
            pa = active_program(cp.user, b)
            days = planned_workout_days(pa, a, b)
            planned += len(days)
            done += min(len(days), WorkoutLog.objects.filter(client=cp.user, status="completed",
                                                             date__range=(a, b)).values("date").distinct().count())
        return round(100 * done / planned) if planned else None

    now_pct, last_pct = pct(end - timedelta(days=6), end), pct(end - timedelta(days=13), end - timedelta(days=7))
    mine_reply = _reply_hours(Submission.objects.filter(reviewed_by=user, reviewed_at__gte=now - timedelta(days=30)))
    team_reply = _reply_hours(Submission.objects.filter(reviewed_at__gte=now - timedelta(days=30)))
    change = None if now_pct is None or last_pct is None else now_pct - last_pct
    return [
        {"key": "clients", "label": "My clients", "value": f"{n} / {tp.max_clients}",
         "delta": f"{max(tp.max_clients - n, 0)} spots free", "tone": ""},
        {"key": "checkins", "label": "Check-ins to review", "value": str(len(waiting)),
         "delta": f"{over} waiting over 48 hours" if over else "None waiting long", "tone": "down" if over else "up"},
        {"key": "workouts", "label": "Workouts done", "value": "—" if now_pct is None else f"{now_pct}%",
         "delta": "" if change is None else f"{'+' if change >= 0 else '−'}{abs(change)}% vs last week",
         "tone": "" if change is None else ("up" if change >= 0 else "down")},
        {"key": "reply", "label": "Avg reply time", "value": _hours(mine_reply),
         "delta": f"Team average {_hours(team_reply)}" if team_reply is not None else "", "tone": ""},
    ]


def today_sessions(user, now):
    from apps.scheduling.models import Session

    tz = timezone.get_current_timezone()
    day = timezone.localdate(now)
    start = timezone.datetime.combine(day, timezone.datetime.min.time(), tz)
    rows = []
    qs = (Session.objects.filter(trainer=user, start__gte=start, start__lt=start + timedelta(days=1))
          .exclude(status="cancelled").select_related("client").order_by("start"))
    nxt = next((s for s in qs if s.status == "booked" and s.start >= now), None)
    for s in qs:
        local = timezone.localtime(s.start)
        mins = round((s.end - s.start).total_seconds() / 60)
        what = " · ".join(x for x in [s.title, "Video call" if s.is_call else (s.place or "Gym floor")] if x)
        row = {"id": str(s.id), "time": f"{local:%H:%M}", "minutes": mins, "client": _person(s.client),
               "what": what, "is_call": s.is_call, "status": s.status, "next": s is nxt, "in": ""}
        if s is nxt:
            left = max(0, round((s.start - now).total_seconds() / 60))
            row["in"] = f"In {left} min" if left < 60 else (f"In {left // 60} h {left % 60} min" if left % 60
                                                            else f"In {left // 60} h")
        rows.append(row)
    return rows


def clients_who_need_you(user, now):
    """Missed workouts · Not logging · Plan ending · Feeling low, worst first (Gautam's board order)."""
    from apps.checkins.models import Submission
    from apps.clients.models import ClientProfile
    from apps.nutrition.models import MealDayState, MealPlanAssignment
    from apps.training.models import AssignmentStatus, ProgramAssignment, WorkoutLog

    today = timezone.localdate(now)
    monday = today - timedelta(days=today.weekday())
    out = []
    mine = (ClientProfile.objects.filter(trainer=user, removed_at__isnull=True, user__status=AccountStatus.ACTIVE)
            .select_related("user"))
    for cp in mine:
        u = cp.user
        base = {**_person(u), "reminded": bool(cp.last_reminded_at and cp.last_reminded_at >= now - timedelta(hours=20))}
        last_w = WorkoutLog.objects.filter(client=u).exclude(status="discarded").order_by("-date").values_list(
            "date", flat=True).first()
        last_m = MealDayState.objects.filter(client=u).order_by("-date").values_list("date", flat=True).first()
        last = max([d for d in (last_w, last_m) if d] or [None]) if (last_w or last_m) else None
        quiet = (today - last).days if last else (today - cp.start_date).days if cp.start_date else 0
        if quiet >= 5:
            out.append({**base, "kind": "log", "why": f"No workout or meal logged in {quiet} days", "action": "remind"})
        else:
            pa = active_program(u)
            planned = planned_workout_days(pa, monday, today - timedelta(days=1))
            if pa:
                week_all = planned_workout_days(pa, monday, monday + timedelta(days=6))
                done = set(WorkoutLog.objects.filter(client=u, status="completed", date__range=(monday, today))
                           .values_list("date", flat=True))
                missed = [d for d in planned if d not in done]
                if len(missed) >= 2:
                    out.append({**base, "kind": "miss", "action": "remind",
                                "why": f"Missed {len(missed)} workouts this week · {len(done)} of {len(week_all)} done"})
        pa = active_program(u)
        if pa and pa.end_date and today <= pa.end_date <= today + timedelta(days=7):
            nxt = ProgramAssignment.objects.filter(client=u, status=AssignmentStatus.UP_NEXT).exists()
            if not nxt:
                when = "today" if pa.end_date == today else f"on {pa.end_date:%A}"
                out.append({**base, "kind": "end", "action": "plan",
                            "why": f"{pa.effective_program.name} ends {when} · nothing up next"})
        else:
            mp = active_meal_plan(u)
            if mp and mp.end_date and today <= mp.end_date <= today + timedelta(days=7) and not \
                    MealPlanAssignment.objects.filter(client=u, status="up_next").exists():
                left = (mp.end_date - today).days
                out.append({**base, "kind": "end", "action": "plan",
                            "why": "Meal plan ends today" if left == 0 else f"Meal plan ends in {left} day{'s' * (left != 1)}"})
        # Feeling low = their latest check-in with energy or mood says 2 / 5 or less (an older low day that has
        # passed does not count, so the trainer and the client's own history agree).
        recent = [x for x in Submission.objects.filter(client=u, form_type__in=["weekly", "daily"],
                                                        created_at__gte=now - timedelta(days=15))
                  .order_by("-created_at")[:6]
                  if x.metrics.get("energy") is not None or x.metrics.get("mood") is not None]

        def low(x):
            e, m = x.metrics.get("energy"), x.metrics.get("mood")
            return (e is not None and e <= 2) or (m is not None and m <= 2)

        if recent and low(recent[0]):
            m0 = recent[0].metrics
            word, v = ("Energy", m0["energy"]) if m0.get("energy") is not None and m0["energy"] <= 2 else ("Mood", m0["mood"])
            two = len(recent) > 1 and low(recent[1])
            out.append({**base, "kind": "low", "action": "open",
                        "why": f"{word} {v:g} / 5 in the last 2 check-ins" if two else f"{word} {v:g} / 5 in the last check-in"})
    order = {"log": 0, "miss": 1, "end": 2, "low": 3}
    out.sort(key=lambda r: order[r["kind"]])
    seen = set()  # one row a client: the worst reason
    return [r for r in out if not (r["id"] in seen or seen.add(r["id"]))]


CHECKIN_ROWS = 5  # the card shows the oldest few; "View all" opens the Check-ins page


def checkins_to_review(user, now):
    from apps.checkins.queue import review_queue
    from apps.checkins.review import review_view

    qs = list(review_queue(user).select_related("client", "form").order_by("created_at"))
    rows = []
    for s in qs[:CHECKIN_ROWS]:
        h = (now - s.created_at).total_seconds() / 3600
        rows.append({"id": str(s.id), "client": _person(s.client), "kind": KIND_LABEL.get(s.form_type, "Check-in"),
                     "line": review_view(s)["line"], "age": _age(h), "hours": round(h),
                     "tone": "bad" if h >= 48 else ("warn" if h >= 24 else "neu")})
    return qs, rows


def this_week(user, now):
    from apps.checkins.models import Submission
    from apps.clients.models import ClientProfile
    from apps.nutrition.models import MealPlanAssignment
    from apps.scheduling.models import Session
    from apps.training.models import ProgramAssignment

    today = timezone.localdate(now)
    monday = today - timedelta(days=today.weekday())
    tz = timezone.get_current_timezone()
    start = timezone.datetime.combine(monday, timezone.datetime.min.time(), tz)
    held = Session.objects.filter(trainer=user, start__gte=start, start__lt=now).exclude(status="cancelled")
    subs = Submission.objects.filter(client__client_profile__trainer=user, form_type__in=["weekly", "survey"],
                                     created_at__gte=start)
    plans = (ProgramAssignment.objects.filter(client__client_profile__trainer=user, created_at__gte=start).count()
             + MealPlanAssignment.objects.filter(client__client_profile__trainer=user, created_at__gte=start).count())
    # New this week = their plan day 1 is this week (or, without a start date, they were added this week).
    new = list(ClientProfile.objects.filter(trainer=user, removed_at__isnull=True)
               .filter(Q(start_date__gte=monday) | Q(start_date__isnull=True, created_at__gte=start))
               .select_related("user").order_by("created_at"))
    names = ", ".join(cp.user.first_name for cp in new[:3])
    return {
        "range": _range(monday, today),
        "rows": [
            {"label": "Sessions held", "value": f"{held.filter(status='done').count()} of {held.count()}"},
            {"label": "Check-ins reviewed", "value": f"{subs.filter(reviewed_at__isnull=False).count()} of {subs.count()}"},
            {"label": "Plans changed", "value": str(plans)},
            {"label": "New clients", "value": f"{len(new)} · {names}" if new else "0"},
        ],
    }


def _when(dt, now=None):
    local = timezone.localtime(dt)
    days = (timezone.localdate(now or timezone.now()) - local.date()).days
    if days == 0:
        return f"{local:%H:%M}"
    if days == 1:
        return "Yesterday"
    return f"{days} days ago" if days < 7 else dfmt(local, "%-d %b")


ACTIVITY_ROWS = 10  # the card shows the latest 10 (Gautam); older pages: dashboard/trainer/activity/?before=
ACTIVITY_TONE = {"checkin": "ci", "plan": "pl", "workout": "cl", "meal": "cl", "body": "cl", "session": "ch"}


def activity(user, before="", now=None, size=ACTIVITY_ROWS):
    """Activity card: what the trainer and their clients did (check-ins sent, workouts, sessions, plan changes),
    newest first, one page at a time. Keyset paging on (created_at, id) so a long log stays quick."""
    from apps.clients.models import ClientProfile

    from .models import ActivityEvent

    mine = ClientProfile.objects.filter(trainer=user, removed_at__isnull=True).values("user_id")
    qs = (ActivityEvent.objects.filter(Q(actor=user) | Q(trainer=user) | Q(client__in=mine))
          .select_related("client", "actor").order_by("-created_at", "-id"))
    if before:
        at, _, pk = before.partition("|")
        try:
            t = timezone.datetime.fromisoformat(at)
            qs = qs.filter(Q(created_at__lt=t) | Q(created_at=t, id__lt=pk))
        except ValueError:
            pass
    rows = list(qs[:size + 1])
    out = []
    for e in rows[:size]:
        me = e.actor_id == user.id
        who = "You" if me else (e.actor_label or "System")
        bits = []
        if e.client_id and e.client_id != e.actor_id:
            bits.append(e.client.full_name)
        if e.target_label and e.target_label not in e.verb and (not e.client_id or e.target_label != e.client.full_name):
            bits.append(e.target_label)
        if e.change_from or e.change_to:
            bits.append(f"{e.change_from or '–'} → {e.change_to or '–'}")
        out.append({"id": str(e.id), "who": who, "me": me, "what": e.verb, "detail": " · ".join(bits),
                    "kind": e.kind, "tone": ACTIVITY_TONE.get(e.kind, ""), "when": _when(e.created_at, now),
                    "client": str(e.client_id) if e.client_id else ""})
    more = len(rows) > size
    last = rows[size - 1] if more else None
    return {"rows": out, "next": f"{last.created_at.isoformat()}|{last.id}" if last else ""}


def notices(user):
    from apps.notifications.models import Notification

    qs = Notification.objects.filter(recipient=user, in_app=True).select_related("actor").order_by("-created_at")[:8]
    now = timezone.now()
    out = []
    for n in qs:
        when = _when(n.created_at, now)
        a = n.actor
        out.append({"id": str(n.id), "title": n.title, "when": when, "read": n.read_at is not None,
                    "initials": a.initials if a else "V", "color": a.avatar_color if a else "c3",
                    "route": (n.data or {}).get("route", "")})
    return out


def trainer_home(user, now=None):
    from apps.clients.models import ClientProfile

    now = now or timezone.now()
    waiting, cis = checkins_to_review(user, now)
    ses = today_sessions(user, now)
    n = ClientProfile.objects.filter(trainer=user, removed_at__isnull=True, user__status=AccountStatus.ACTIVE).count()
    local = timezone.localtime(now)
    nts = notices(user)
    return {
        "greeting": _greeting(user, now),
        "date": f"{local:%a}, {local.day} {local:%b}",
        "subline": f"{local:%A}, {local.day} {local:%B} · {n} client{'s' * (n != 1)} · "
                   f"{len(ses)} session{'s' * (len(ses) != 1)} today",
        "stats": stats(user, now, waiting),
        "today": ses,
        "need": clients_who_need_you(user, now),
        "checkins": cis,
        "checkins_total": len(waiting),
        "week": this_week(user, now),
        "activity": activity(user, now=now),
        "notices": nts,
        "unread": sum(1 for x in nts if not x["read"]),
    }
