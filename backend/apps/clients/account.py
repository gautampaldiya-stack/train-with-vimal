"""Client More tab (boards ClientMore / ClientMoreWeb): the account page, My activity and Download my data.

`account_page` answers everything the More page, the Profile page and the coach Details sheet show, so the tab
opens with one request (and from the cache when offline). Weights are in kg; the app shows them in the
client's unit.
"""
import io
import json
import logging
import uuid
import zipfile
from datetime import datetime, time, timedelta

from celery import shared_task
from django.conf import settings
from django.core.files.storage import default_storage
from django.utils import timezone

from apps.common.utils import dfmt

log = logging.getLogger(__name__)

GOAL_TITLE = {"fat_loss": "lose fat", "muscle_gain": "build muscle", "strength": "get stronger",
              "recomp": "recomp", "general": "get fitter", "event": "event prep"}
ACTIVITY_DAYS = 7
EXPORT_DIR = "exports"
EXPORT_KEEP_DAYS = 7


def _f(v):
    return float(v) if v is not None else None


def _age(dob, today):
    return today.year - dob.year - ((today.month, today.day) < (dob.month, dob.day))


def _names(items, n=3, last=", "):
    """A, B, C · A, B and 2 more (last=" and " → A, B and C)."""
    if len(items) <= n:
        return last.join([", ".join(items[:-1]), items[-1]]) if len(items) > 1 else "".join(items)
    return ", ".join(items[:n]) + f" and {len(items) - n} more"


def _lower(name):
    """"Vitamin D3" → "vitamin D3": lower only the first letter, so D3 stays D3."""
    return name[:1].lower() + name[1:] if name[1:2].islower() else name


def account_page(client, request=None):
    from apps.checkins.client_page import DAILY_REMINDER, WEEKLY_DUE
    from apps.checkins.models import Submission, WeightLog
    from apps.checkins.progress import _goal_eta
    from apps.checkins.services import week_number
    from apps.gym.models import GymSettings
    from apps.habits.models import HabitAssignment, SupplementAssignment
    from apps.notifications.models import ReminderPreference
    from apps.notifications.services import unread_count
    from apps.scheduling.models import Session

    from .metrics import active_meal_plan, active_program, program_day_for

    today = timezone.localdate()
    cp = client.client_profile
    coach = cp.trainer
    first = coach.first_name if coach else "your coach"
    since = cp.start_date or client.date_joined.date()

    # Plan
    pa = active_program(client, today)
    program = None
    if pa:
        prog = pa.effective_program
        ends = pa.end_date or (pa.start_date + timedelta(weeks=prog.weeks) - timedelta(days=1))
        days = [today - timedelta(days=today.weekday()) + timedelta(days=i) for i in range(7)]
        train = [d for d in days if (pd := program_day_for(pa, d)) is not None and not pd.is_rest]
        program = {"name": prog.name, "week": min(week_number(client, today), prog.weeks), "weeks": prog.weeks,
                   "start": pa.start_date, "end": ends, "training_days": [d.weekday() for d in train]}
    mp = active_meal_plan(client, today)
    meal = {"kcal": mp.plan.kcal_target, "diet": mp.plan.get_diet_display().lower(),
            "water_ml": mp.plan.water_ml} if mp else None

    # Weekly check-in: every Sunday at 6 pm; "next" is this Sunday until this week's is sent.
    sunday = today + timedelta(days=6 - today.weekday())
    sent_this_week = Submission.objects.filter(client=client, form_type="weekly",
                                               date__gte=sunday - timedelta(days=6)).exists()
    next_ci = sunday + timedelta(days=7) if sent_this_week else sunday
    sent_count = Submission.objects.filter(client=client, form_type="weekly").count()

    # Goal
    weights = list(WeightLog.objects.filter(client=client).order_by("date"))
    start_kg = _f(cp.start_weight_kg) if cp.start_weight_kg is not None else (
        _f(weights[0].weight_kg) if weights else None)
    now_kg = _f(weights[-1].weight_kg) if weights else _f(cp.current_weight_kg)
    goal_kg = _f(cp.target_weight_kg)
    goal = None
    if cp.goal or goal_kg is not None:
        pct = None
        if None not in (start_kg, now_kg, goal_kg) and start_kg != goal_kg:
            pct = max(0, min(100, round((start_kg - now_kg) / (start_kg - goal_kg) * 100)))
        goal = {"title": GOAL_TITLE.get(cp.goal, "reach your goal weight"), "start_kg": start_kg, "now_kg": now_kg,
                "goal_kg": goal_kg, "pct": pct, "eta": _goal_eta(weights, goal_kg, today),
                "start_date": weights[0].date if weights else since}

    # Coach
    session = (Session.objects.filter(client=client, start__gte=timezone.now() - timedelta(hours=1), status="booked")
               .order_by("start").first())
    nxt = None
    if session:
        nxt = {"id": str(session.id), "start": session.start, "end": session.end, "place": session.place or "",
               "minutes": round((session.end - session.start).total_seconds() / 60), "is_call": session.is_call}

    habits = [_short_habit(a.habit) for a in HabitAssignment.objects.filter(client=client, active=True)
              .select_related("habit").order_by("created_at")]
    supps = [_short_supp(i.name) for a in SupplementAssignment.objects.filter(client=client, active=True)
             .prefetch_related("plan__items") for i in a.plan.items.all()]

    gym = GymSettings.load()
    prefs = ReminderPreference.objects.get_or_create(user=client)[0]
    deletion = None
    if client.deletion_requested_at:
        from apps.accounts.views import DeleteAccountView

        deletion = (timezone.localtime(client.deletion_requested_at)
                    + timedelta(days=DeleteAccountView.GRACE_DAYS)).date()
    return {
        "profile": {
            "name": client.full_name, "initials": client.initials, "avatar_color": client.avatar_color,
            "avatar": request.build_absolute_uri(client.avatar.url) if (request and client.avatar) else None,
            "email": client.email or "", "pending_email": client.pending_email or "", "phone": client.phone or "",
            "city": client.city, "date_of_birth": client.date_of_birth,
            "age": _age(client.date_of_birth, today) if client.date_of_birth else None,
            "height_cm": _f(cp.height_cm), "since": since,
        },
        "coach": {"name": coach.full_name, "first_name": first, "initials": coach.initials,
                  "avatar_color": coach.avatar_color, "since": since} if coach else None,
        "next_session": nxt,
        "checkin": {"weekday": 6, "time": WEEKLY_DUE, "next": next_ci, "week": week_number(client, next_ci),
                    "due_this_week": not sent_this_week, "reply": f"{first} replies by Monday evening"},
        "program": program,
        "meal_plan": meal,
        "goal": goal,
        "stats": {"lost_kg": round(start_kg - now_kg, 1) if None not in (start_kg, now_kg) else None,
                  "checkins_sent": sent_count},
        "habits": {"habits": habits, "supplements": supps},
        "daily": {"sent_today": Submission.objects.filter(client=client, form_type="daily", date=today).exists(),
                  "reminder": DAILY_REMINDER},
        "unread": unread_count(client),
        "reminders": {k: getattr(prefs, k) for k in ("workout", "meal", "water", "supps", "habit", "checkin",
                                                     "trainer_reply", "progress", "quiet_on")}
        | {"quiet_from": prefs.quiet_from, "quiet_to": prefs.quiet_to},
        "deletion_on": deletion,
        "gym": {"name": gym.name, "phone": gym.phone, "email": gym.email, "hours": "6 am to 10 pm"},
        "version": getattr(settings, "APP_VERSION", "1.0.0"),
    }


# ─────────────────────────────── My activity


def _short_habit(h):
    """"8,000 steps" → steps, "Drink 3 L water" → water: the More row lists what is tracked, not the targets."""
    text = f"{h.name} {h.unit}".lower()
    for word in ("steps", "water", "sleep", "protein", "stretch", "sugar"):
        if word.rstrip("s") in text:
            return word
    return h.name.lower()


def _short_supp(name):
    """"Whey protein" → whey, "Vitamin D3" → D3, "Magnesium glycinate" → magnesium."""
    words = name.split()
    if len(words) > 1 and words[0].lower() == "vitamin":
        return words[1]
    w = words[0] if words else name
    return w if any(c.isdigit() for c in w) or w.isupper() else w.lower()


def _clock(dt):
    return dfmt(timezone.localtime(dt), "%-I:%M %p").lower()


def my_activity(client, kind="All"):
    """Everything the client logged in the last 7 days, newest first, grouped by day.
    kind = All | Training | Food | Check-ins | Habits | Account."""
    from apps.activity.models import ActivityEvent
    from apps.checkins.models import MEASURE_KEYS, MEASURES, Measurement, Submission, WeightLog
    from apps.habits.models import HabitLog, SupplementLog
    from apps.nutrition.models import FoodLogEntry, MealDayState
    from apps.training.models import ProgramExercise, WorkoutLog

    today = timezone.localdate()
    start = today - timedelta(days=ACTIVITY_DAYS - 1)
    tz = timezone.get_current_timezone()
    out = []

    def add(k, at, icon, color, title, sub, rows, link=None, label=None, day=None):
        """`day` = the day the log is for (a weigh-in for yesterday logged this morning goes under yesterday)."""
        at = timezone.localtime(at)
        day = day or at.date()
        if at.date() != day:  # sort it by its own day, keeping the clock time it was logged at
            at = timezone.make_aware(datetime.combine(day, at.time()), tz)
        out.append({"k": k, "at": at, "date": day, "time": _clock(at), "icon": icon, "color": color,
                    "title": title, "sub": sub, "rows": rows, "link": link, "label": label})

    if kind in ("All", "Training"):
        for w in (WorkoutLog.objects.filter(client=client, status="completed", date__range=(start, today))
                  .prefetch_related("sets__exercise")):
            done = [s for s in w.sets.all() if s.done and not s.is_warmup]
            exs = {s.exercise_id for s in done}
            prs = [s for s in done if s.is_pr]
            mins = round(w.duration_seconds / 60) if w.duration_seconds else None
            top = max(done, key=lambda s: float(s.weight_kg or 0), default=None)
            name = w.name or "Workout"
            planned = ProgramExercise.objects.filter(day_id=w.program_day_id).count() if w.program_day_id else 0
            ex_line = f"{len(exs)} of {max(planned, len(exs))} exercises"
            rows = [["Duration", f"{mins} min"]] if mins else []
            rows.append(["Exercises", ex_line.replace(" exercises", "")])
            if prs:
                b = max(prs, key=lambda s: float(s.weight_kg or 0))
                rows.append(["Personal best", f"{b.exercise.name} {float(b.weight_kg):g} kg × {b.reps or 1}"])
            elif top is not None and top.weight_kg:
                rows.append(["Top set", f"{top.exercise.name} {float(top.weight_kg):g} kg × {top.reps or 1}"])
            sub = " · ".join(([f"{mins} min"] if mins else []) + [ex_line])
            if prs:
                b = max(prs, key=lambda s: float(s.weight_kg or 0))
                add("Training", w.finished_at or w.started_at, "star", "amber",
                    f"Completed {name} · {len(prs)} personal best{'s' if len(prs) > 1 else ''}",
                    f"{mins} min · {b.exercise.name.lower()} {float(b.weight_kg):g} kg × {b.reps or 1}" if mins else
                    sub, rows, "/progress", "See progress", day=w.date)
            else:
                add("Training", w.finished_at or w.started_at, "dumb", "blue", f"Completed {name}", sub, rows,
                    "/train", "Open training", day=w.date)

    if kind in ("All", "Food"):
        states = (MealDayState.objects.filter(client=client, date__range=(start, today))
                  .select_related("meal").order_by("date"))
        food = list(FoodLogEntry.objects.filter(client=client, date__range=(start, today)).order_by("logged_at"))
        for s in states:
            if s.status == "logged" and s.logged_at:
                names = [e.name for e in food if e.date == s.date and e.meal_id == s.meal_id and e.source == "plan"]
                kc = sum(e.kcal for e in food if e.date == s.date and e.meal_id == s.meal_id)
                add("Food", s.logged_at, "food", "green", f"Logged {s.meal.name.lower()}", _names(names) or "As planned",
                    [[s.meal.name, _names(names, 4) or "As planned"], ["Calories", f"About {kc:,} kcal"]],
                    "/food", "Open meal plan", day=s.date)
            if s.swaps:
                add("Food", s.updated_at, "food", "green", f"Swapped a food at {s.meal.name.lower()}",
                    f"{s.meal.name} · that day only", [["Meal", s.meal.name], ["Swaps", str(len(s.swaps))]],
                    "/food", "Open meal plan", day=s.date)
        for e in food:
            if e.source != "plan" or not e.meal_id:
                add("Food", e.logged_at, "food", "green", f"Logged {e.name}", f"{e.meal_name} · {e.kcal:,} kcal",
                    [["Food", e.name], ["Amount", f"{float(e.quantity):g} {e.unit_name}"], ["Calories", f"{e.kcal:,} kcal"],
                     ["Protein", f"{float(e.protein):g} g"]], "/food", "Open meal plan", day=e.date)

    if kind in ("All", "Check-ins"):
        weights = list(WeightLog.objects.filter(client=client, date__lte=today).order_by("date"))
        for i, w in enumerate(weights):
            if w.date < start:
                continue
            prev = weights[i - 1] if i else None
            diff = float(w.weight_kg - prev.weight_kg) if prev else None
            way = "" if diff is None else ("same as" if diff == 0 else
                                          f"{abs(diff):.1f} kg {'down' if diff < 0 else 'up'} since")
            sub = f"{float(w.weight_kg):.1f} kg" + (f" · {way} {dfmt(prev.date, '%a, %-d %b')}" if prev else "")
            rows = [["Weight", f"{float(w.weight_kg):.1f} kg"]]
            if prev:
                rows.append(["Change", f"{way} {dfmt(prev.date, '%a, %-d %b')}"])
            if weights[0] is not w:
                tot = float(w.weight_kg - weights[0].weight_kg)
                rows.append(["Since start", f"{abs(tot):.1f} kg {'down' if tot < 0 else 'up'}"])
            on = timezone.localtime(w.created_at).date()
            if on != w.date:
                rows.append(["Logged on", dfmt(on, "%a, %-d %b")])
            add("Check-ins", w.created_at, "scale", "amber", "Logged weight", sub, rows, "/progress", "See progress",
                day=w.date)
        names = {k: (lbl, u) for k, lbl, u in MEASURES}
        for m in Measurement.objects.filter(client=client, date__range=(start, today)):
            rows = [[names.get(k, (k, ""))[0], f"{v:g} {names.get(k, (k, ''))[1]}".strip()]
                    for k, v in sorted(m.values.items(), key=lambda kv: MEASURE_KEYS.index(kv[0])
                                       if kv[0] in MEASURE_KEYS else 99)]
            on = timezone.localtime(m.created_at).date()
            if on != m.date:  # filled in later: say when
                rows.append(["Logged on", dfmt(on, "%a, %-d %b")])
            add("Check-ins", m.created_at, "scale", "amber", "Logged measurements",
                f"{len(m.values)} measurement{'s' if len(m.values) != 1 else ''}", rows, "/progress",
                "See progress", day=m.date)
        for s in Submission.objects.filter(client=client, date__range=(start, today),
                                           form_type__in=["weekly", "daily"]):
            mt = s.metrics or {}
            photos = s.answers.exclude(photo="").exclude(photo__isnull=True).count()
            weekly = s.form_type == "weekly"
            title = (f"Sent week {s.week_number} check-in" if s.week_number else "Sent weekly check-in") if weekly \
                else "Sent daily check-in"
            bits = ([f"{mt['weight']:g} kg"] if mt.get("weight") else []) + \
                ([f"{photos} photo{'s' if photos != 1 else ''}"] if photos else [])
            rows = ([["Weight", f"{mt['weight']:g} kg"]] if mt.get("weight") else []) + \
                ([["Your note", f"“{s.note}”"]] if getattr(s, "note", "") else []) + \
                [["Reply", f"Replied on {dfmt(timezone.localtime(s.reviewed_at), '%a, %-d %b')}"
                  if s.reply and s.reviewed_at else "Waiting for a reply"]]
            add("Check-ins", s.created_at, "form", "amber", title, " · ".join(bits) or "Sent", rows,
                f"/checkins/{s.id}", "Open check-ins", day=s.date)

    if kind in ("All", "Habits"):
        logs = (SupplementLog.objects.filter(client=client, date__range=(start, today))
                .select_related("item").order_by("taken_at"))
        by_day = {}
        for lg in logs:
            by_day.setdefault(lg.date, []).append(lg)
        for d, lgs in by_day.items():
            names = [lg.item.name for lg in lgs]
            add("Habits", lgs[-1].taken_at, "pill", "purple", f"Took {_names([_lower(x) for x in names], 2, ' and ')}",
                f"{len(lgs)} supplement{'s' if len(lgs) != 1 else ''}",
                [[lg.item.name, f"{lg.item.dose} · {_clock(lg.taken_at)}"] for lg in lgs], "/habits", "Open habits",
                day=d)
        for h in (HabitLog.objects.filter(client=client, date__range=(start, today))
                  .select_related("habit")):
            hb = h.habit
            if not h.value and (not h.done or hb.kind != "tick"):  # a number habit at 0 is not a log
                continue
            unit = (hb.unit or "").lower()
            at = h.updated_at if timezone.localtime(h.updated_at).date() == h.date else \
                timezone.make_aware(datetime.combine(h.date, time(21, 0)), tz)
            if "step" in unit or "step" in hb.name.lower():
                met = hb.target and h.value >= hb.target
                add("Habits", at, "steps", "green", f"Walked {h.value:,} steps",
                    "Step goal met" if met else f"Goal {hb.target:,}" if hb.target else "Steps",
                    [["Steps", f"{h.value:,}" + (f" of {hb.target:,}" if hb.target else "")]], "/habits", "Open habits")
            elif "sleep" in hb.name.lower() or unit in ("min", "minutes"):
                hrs, mins = divmod(h.value, 60)
                met = hb.target and h.value >= hb.target
                add("Habits", at, "moon", "purple", "Logged sleep",
                    f"{hrs} h {mins} min" + (" · goal met" if met else ""),
                    [["Sleep", f"{hrs} h {mins} min"]] + ([["Goal", f"{hb.target // 60} hours"]] if hb.target else []),
                    "/habits", "Open habits")
            elif "water" in hb.name.lower():
                met = hb.target and h.value >= hb.target
                add("Habits", at, "target", "green", f"Drank {h.value:,} {hb.unit or 'glasses'} of water".replace("  ", " "),
                    "Water goal met" if met else f"Goal {hb.target:,} {hb.unit}".strip() if hb.target else "Water",
                    [["Water", f"{h.value:,} {hb.unit}".strip() + (f" of {hb.target:,}" if hb.target else "")]],
                    "/habits", "Open habits")
            elif hb.kind == "tick":
                add("Habits", at, "target", "green", f"Done: {hb.name}", "Habit ticked", [["Habit", hb.name]],
                    "/habits", "Open habits")
            else:
                add("Habits", at, "target", "green", f"{hb.name}: {h.value:,} {hb.unit}".strip(),
                    "Goal met" if hb.target and h.value >= hb.target else "Logged",
                    [[hb.name, f"{h.value:,} {hb.unit}".strip()]], "/habits", "Open habits")

    # Lines the client's own changes left (profile, preferences, a past weigh-in or measurement edited).
    for ev in ActivityEvent.objects.filter(actor=client, client=client, meta__has_key="mine",
                                           created_at__date__gte=start):
        m = ev.meta["mine"]
        k = m.get("k", "Account")
        if kind in ("All", k):
            add(k, ev.created_at, m.get("icon", "user"), m.get("color", "gray"), m["t"], m["s"], m["rows"],
                m.get("link"), m.get("label"))

    out.sort(key=lambda a: a["at"], reverse=True)
    days = []
    for a in out:
        if not days or days[-1]["date"] != a["date"]:
            days.append({"date": a["date"], "items": []})
        a.pop("at")
        days[-1]["items"].append(a)
    return {"kind": kind, "from": start, "to": today, "count": len(out), "days": days}


# ─────────────────────────────── Download my data


def _rows(qs, fields):
    return [{f: (str(v) if not isinstance(v, (int, float, str, bool, type(None), list, dict)) else v)
             for f, v in zip(fields, r)} for r in qs.values_list(*fields)]


def build_export(client):
    """A ZIP with the profile, workouts, food logs, check-ins and photos. Returns the storage path."""
    from apps.checkins.models import Answer, Measurement, ProgressPhoto, Submission, WeightLog
    from apps.habits.models import HabitLog, SupplementLog
    from apps.nutrition.models import FoodLogEntry, WaterLog
    from apps.training.models import SetLog, WorkoutLog

    data = {
        "profile": {"name": client.full_name, "email": client.email, "phone": client.phone, "city": client.city,
                    "date_of_birth": str(client.date_of_birth or ""), "joined": str(client.date_joined.date())},
        "workouts": _rows(WorkoutLog.objects.filter(client=client).order_by("date"),
                          ["date", "name", "status", "duration_seconds", "effort", "note", "sets_done"]),
        "sets": _rows(SetLog.objects.filter(workout__client=client).order_by("workout__date"),
                      ["workout__date", "exercise__name", "weight_kg", "reps", "seconds", "distance_km", "done",
                       "is_pr"]),
        "food_log": _rows(FoodLogEntry.objects.filter(client=client).order_by("logged_at"),
                          ["date", "meal_name", "name", "quantity", "unit_name", "kcal", "protein", "carbs", "fat"]),
        "water": _rows(WaterLog.objects.filter(client=client).order_by("date"), ["date", "ml"]),
        "weights": _rows(WeightLog.objects.filter(client=client).order_by("date"), ["date", "weight_kg"]),
        "measurements": _rows(Measurement.objects.filter(client=client).order_by("date"), ["date", "values"]),
        "checkins": _rows(Submission.objects.filter(client=client).order_by("date"),
                          ["date", "form_type", "week_number", "metrics", "reply"]),
        "answers": _rows(Answer.objects.filter(submission__client=client).exclude(question__type="photo"),
                         ["submission__date", "question__text", "value"]),
        "habits": _rows(HabitLog.objects.filter(client=client).order_by("date"), ["date", "habit__name", "value", "done"]),
        "supplements": _rows(SupplementLog.objects.filter(client=client).order_by("date"), ["date", "item__name"]),
    }
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("my-data.json", json.dumps(data, indent=2, ensure_ascii=False, default=str))
        for p in ProgressPhoto.objects.filter(photo_set__client=client).select_related("photo_set"):
            try:
                with p.image.open("rb") as f:
                    z.writestr(f"photos/{p.photo_set.date}-{p.pose}.{p.image.name.rsplit('.', 1)[-1]}", f.read())
            except (OSError, ValueError):
                log.warning("export: photo %s missing", p.id)
    path = f"{EXPORT_DIR}/{client.id}/{uuid.uuid4().hex}.zip"
    from django.core.files.base import ContentFile

    return default_storage.save(path, ContentFile(buf.getvalue()))


@shared_task
def send_data_export(user_id, base_url=""):
    from django.contrib.auth import get_user_model
    from django.core.mail import send_mail

    user = get_user_model().objects.filter(id=user_id).first()
    if user is None or not user.email:
        return None
    path = build_export(user)
    url = default_storage.url(path)
    if base_url and url.startswith("/"):
        url = base_url.rstrip("/") + url
    send_mail(
        "Your Train With Vimal data",
        f"Hi {user.first_name},\n\nYour data is ready: {url}\n\nThe link works for {EXPORT_KEEP_DAYS} days. "
        "It has your profile, workouts, food logs, check-ins and photos.\n\nTrain With Vimal",
        None, [user.email])
    return path


@shared_task
def purge_data_exports():
    """Download links work for 7 days."""
    cutoff = timezone.now() - timedelta(days=EXPORT_KEEP_DAYS)
    gone = 0
    try:
        users, _ = default_storage.listdir(EXPORT_DIR)
    except (FileNotFoundError, NotImplementedError):
        return 0
    for u in users:
        for name in default_storage.listdir(f"{EXPORT_DIR}/{u}")[1]:
            p = f"{EXPORT_DIR}/{u}/{name}"
            if default_storage.get_modified_time(p) < cutoff:
                default_storage.delete(p)
                gone += 1
    return gone
