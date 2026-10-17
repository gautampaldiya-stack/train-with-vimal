"""Client app → Check-ins page (boards ClientCheckin / ClientCheckinWeb).

The weekly check-in is due every Sunday at 6:00 pm (a calendar week, Monday to Sunday). A week with no
weekly check-in is shown as Missed; a day with no daily check-in is shown as Missed (after the 9 pm
reminder). History is paged with `before` (a date), newest first.
"""
from datetime import datetime, time, timedelta

from django.utils import timezone

from .defaults import CHIPS
from .models import MEASURE_KEYS, Form, QuestionType, Submission, WeightLog

WEEKLY_DUE = time(18, 0)  # Sunday 6:00 pm
DAILY_REMINDER = "9:00 pm"
PAGE = 20


def _monday(d):
    return d - timedelta(days=d.weekday())


def _due_at(sunday):
    return timezone.make_aware(datetime.combine(sunday, WEEKLY_DUE))


def _start(client):
    cp = client.client_profile
    return cp.start_date or client.date_joined.date()


def _chip(q):
    from .services import photo_slots

    if q.type == QuestionType.PHOTO:
        n = len(photo_slots(q))
        return "1 photo" if n == 1 else f"{n} photos"
    if q.text in CHIPS:
        return CHIPS[q.text]
    if q.metric == "weight":
        return "Weight"
    t = q.text.rstrip("?").strip()
    return t if len(t) <= 18 else t[:17].rstrip() + "…"


MEASURES_Q = -1  # the "Body measurements" step: not a stored question, its answer is {key: number}


def measures_question(client):
    """Photo weeks of the weekly check-in also ask the coach's measurements (D-24). One step, all optional;
    the numbers go to Progress on submit. Each row starts from the last value logged."""
    from .models import DEFAULT_MEASURES, MEASURES, Measurement

    keys = client.client_profile.measure_keys or DEFAULT_MEASURES
    last = {}
    for m in Measurement.objects.filter(client=client).order_by("-date")[:60]:
        for k, v in m.values.items():
            last.setdefault(k, (v, m.date))
    rows = [{"key": k, "label": lbl, "unit": u, "last": last.get(k, (None, None))[0],
             "last_date": last.get(k, (None, None))[1]} for k, lbl, u in MEASURES if k in keys]
    return {"id": MEASURES_Q, "text": "Body measurements", "type": "measures", "options": [], "scale_labels": [],
            "allow_other": False, "help_text": "Relaxed, tape snug but not tight. Change only what you measured.",
            "required": False, "metric": "", "chip": "Measurements", "measures": rows}


def form_payload(form, coach_first, photos=True, client=None):
    """`photos=False` on the off weeks of "photos every N weeks": the photo question is left out.
    With `client` on a photo week, a "Body measurements" step goes in just before the photos."""
    if form is None:
        return None
    qs = [q for q in form.questions.all() if not q.is_removed and (photos or q.type != QuestionType.PHOTO)]
    out = [{
        "id": q.id, "text": q.text, "type": q.type, "options": q.options, "scale_labels": q.scale_labels,
        "allow_other": q.allow_other, "help_text": q.help_text.replace("{coach}", coach_first or "your coach"),
        "required": q.required, "metric": q.metric, "chip": _chip(q)} for q in qs]
    # Skipped when this period already has its entry (logged from Progress): one entry per period (D-25).
    from .services import measure_entry

    if photos and client is not None and form.type == "weekly" and \
            not any(q.metric in MEASURE_KEYS for q in qs) and measure_entry(client) is None:
        at = next((i for i, q in enumerate(qs) if q.type == QuestionType.PHOTO), len(out))
        out.insert(at, measures_question(client))
    return {"id": str(form.id), "name": form.name, "type": form.type, "questions": out}


def _week_counts(client, monday):
    """Workouts done / planned and the share of planned meals logged, Monday to Sunday."""
    from apps.clients.metrics import active_meal_plan, active_program, planned_workout_days
    from apps.nutrition.models import MealDayState
    from apps.training.models import WorkoutLog

    sunday = monday + timedelta(days=6)
    end = min(sunday, timezone.localdate())
    planned = len(planned_workout_days(active_program(client, end), monday, sunday))
    done = (WorkoutLog.objects.filter(client=client, status=WorkoutLog.Status.COMPLETED, date__range=(monday, end))
            .values("date").distinct().count())
    mp = active_meal_plan(client, end)
    meals = None
    if mp:
        days = max(0, (end - max(monday, mp.start_date)).days + 1)
        want = mp.plan.meals.count() * days
        if want:
            got = MealDayState.objects.filter(client=client, date__range=(monday, end),
                                              status=MealDayState.Status.LOGGED).count()
            meals = round(100 * min(got, want) / want)
    return {"workouts_done": done, "workouts_planned": planned, "meals_pct": meals}


def _habit_day(client, day):
    """Steps and water for one day (the daily check-in takes them from Habits)."""
    from apps.habits.models import HabitLog
    from apps.nutrition.models import WaterLog

    steps = (HabitLog.objects.filter(client=client, date=day, habit__icon="steps").values_list("value", flat=True)
             .first())
    water = WaterLog.objects.filter(client=client, date=day).values_list("ml", flat=True).first()
    return {"steps": steps, "water_ml": water}


def _row(sub):
    m = sub.metrics or {}
    return {"id": str(sub.id), "kind": "sent", "date": sub.date, "sent_at": sub.created_at,
            "week_number": sub.week_number, "metrics": m, "reviewed": sub.reviewed_at is not None,
            "reviewed_at": sub.reviewed_at, "reply": sub.reply, "edited_at": sub.edited_at,
            "photo_count": getattr(sub, "n_photos", 0)}


def answer_photos(sub, request=None):
    """[{question, slot, label, image}] in the order the question asks for them."""
    from .services import photo_slots, slot_key

    out, n = [], {}
    staff = request is not None and not getattr(request.user, "is_client", True)
    # Photos sent while "Share progress photos with Aman" was off stay with the client.
    for a in sorted((a for a in sub.answers.select_related("question") if a.photo and not (staff and a.private)),
                    key=lambda a: a.id):
        slots = photo_slots(a.question)
        i = n[a.question_id] = n.get(a.question_id, -1) + 1  # photos sent before slots had names: in order
        label = a.value if isinstance(a.value, str) and a.value else slots[min(i, len(slots) - 1)]
        url = a.photo.url
        out.append({"question": a.question_id, "slot": slot_key(label), "pose": slot_key(label), "label": label,
                    "image": request.build_absolute_uri(url) if request else url,
                    "_i": slots.index(label) if label in slots else 99})
    out.sort(key=lambda p: (p["question"], p.pop("_i")))
    return out


def full_row(sub, request=None):
    """Today's daily or this week's weekly: the row plus every answer (for Edit answers and the summary)."""
    if sub is None:
        return None
    r = _row(sub)
    r["answers"] = {str(a.question_id): a.value for a in sub.answers.all() if not a.photo}
    r["photos"] = answer_photos(sub, request)
    r["photo_count"] = len(r["photos"])
    return r


def _photo_counts(subs):
    from django.db.models import Count, Q

    ids = [s.id for s in subs]
    counts = dict(Submission.objects.filter(id__in=ids).annotate(
        n=Count("answers", filter=Q(answers__photo__gt=""))).values_list("id", "n"))
    for s in subs:
        s.n_photos = counts.get(s.id, 0)


def weekly_rows(client, before=None):
    from .services import week_number

    today = timezone.localdate()
    this_monday = _monday(today)
    start = _start(client)
    subs = list(Submission.objects.filter(client=client, form_type="weekly").order_by("-date", "-created_at"))
    _photo_counts(subs)
    by_week = {}
    for s in subs:
        by_week.setdefault(_monday(s.date), []).append(s)
    rows = []
    for s in subs:
        r = _row(s)
        r["week_number"] = s.week_number or week_number(client, s.date)
        r["on_time"] = s.created_at <= _due_at(_monday(s.date) + timedelta(days=6))
        rows.append(r)
    # Missed: every finished week since the start with nothing sent.
    m = _monday(start)
    while m < this_monday:
        sunday = m + timedelta(days=6)
        if sunday >= start and m not in by_week:
            rows.append({"id": None, "kind": "missed", "date": sunday, "week_number": week_number(client, sunday),
                         "due_at": _due_at(sunday)})
        m += timedelta(days=7)
    rows.sort(key=lambda r: (r["date"], r.get("sent_at") or _due_at(r["date"])), reverse=True)
    # Weight change against the check-in before (the label says "In 2 weeks" across a gap).
    sent = [r for r in rows if r["kind"] == "sent"]
    for i, r in enumerate(sent):
        w = r["metrics"].get("weight")
        prev = next((p for p in sent[i + 1:] if p["metrics"].get("weight") is not None), None)
        if w is not None and prev is not None:
            r["change_kg"] = round(float(w) - float(prev["metrics"]["weight"]), 1)
            r["change_weeks"] = max(1, round((r["date"] - prev["date"]).days / 7))
    return rows


def daily_rows(client, form):
    today = timezone.localdate()
    start = max(_start(client), today - timedelta(days=365))
    subs = list(Submission.objects.filter(client=client, form_type="daily", date__gte=start).order_by("-date"))
    rows = [_row(s) for s in subs]
    if form is not None:
        have = {s.date for s in subs}
        d = today - timedelta(days=1)
        while d >= start:
            if d not in have:
                rows.append({"id": None, "kind": "missed", "date": d, "reminder": DAILY_REMINDER})
            d -= timedelta(days=1)
    rows.sort(key=lambda r: r["date"], reverse=True)
    return rows


def page(rows, before=None, size=PAGE):
    if before:
        rows = [r for r in rows if r["date"] < before]
    return rows[:size], len(rows) > size


def client_weekly_form(client):
    """Her own copy of the weekly check-in when the coach edited it for her (None after "Stop sending"),
    else the library's weekly check-in."""
    own = (Form.objects.filter(type="weekly", status=Form.Status.CLIENT, client=client)
           .prefetch_related("questions").order_by("-created_at").first())
    if own is not None:
        return own if own.sending else None
    return Form.objects.filter(type="weekly", status="published").prefetch_related("questions").first()


def checkins_page(client, tab="weekly", before=None, request=None):
    from apps.clients.metrics import active_program

    from .services import next_photos_due, photo_week, streak, week_number

    today = timezone.localdate()
    cp = client.client_profile
    coach = cp.trainer
    coach_first = coach.first_name if coach else ""
    weekly = client_weekly_form(client)
    daily = Form.objects.filter(type="daily", status="published").prefetch_related("questions").first()

    w_rows = weekly_rows(client)
    sent_w = [r for r in w_rows if r["kind"] == "sent"]
    due_weeks = [r for r in w_rows if r["kind"] == "missed" or _monday(r["date"]) < _monday(today)]
    this_week = next((r for r in sent_w if _monday(r["date"]) == _monday(today)), None)
    due_total = len(due_weeks) + (1 if this_week else 0)
    on_time = len([r for r in sent_w if r.get("on_time")])
    last_change = next((r.get("change_kg") for r in sent_w if r.get("change_kg") is not None), None)

    all_rows = daily_rows(client, daily) if tab == "daily" else w_rows
    # Past check-ins header: "12 sent · 3 missed" over the whole list, so the count shows before scrolling.
    totals = {"all": len(all_rows), "sent": len([r for r in all_rows if r["kind"] != "missed"]),
              "missed": len([r for r in all_rows if r["kind"] == "missed"])}
    if tab == "daily":
        rows, more = page(all_rows, before)
        for r in rows:
            r.update(_habit_day(client, r["date"]))
    else:
        rows, more = page(all_rows, before)
        for r in rows:
            r.update(_week_counts(client, _monday(r["date"])))

    d_today = Submission.objects.filter(client=client, form_type="daily", date=today).first()
    last_w = WeightLog.objects.filter(client=client, date__lt=today).order_by("-date").first()
    today_w = WeightLog.objects.filter(client=client, date=today).first()
    prev_weekly_w = next((r["metrics"]["weight"] for r in sent_w
                          if r["metrics"].get("weight") is not None and r is not this_week), None)
    pa = active_program(client, today)
    sunday = _monday(today) + timedelta(days=6)
    return {
        "coach": {"name": coach.full_name, "first_name": coach_first, "initials": coach.initials,
                  "avatar_color": coach.avatar_color} if coach else None,
        "program": {"name": pa.effective_program.name, "week": week_number(client, today),
                    "weeks": pa.effective_program.weeks} if pa else None,
        "stats": {"streak": streak(client, "daily"), "weekly_on_time": on_time, "weekly_due": due_total,
                  "last_change_kg": last_change},
        "daily": {"date": today, "form": form_payload(daily, coach_first),
                  "sent": full_row(d_today, request), **_habit_day(client, today),
                  "last_weight": {"date": last_w.date, "kg": float(last_w.weight_kg)} if last_w else None,
                  "today_weight": float(today_w.weight_kg) if today_w else None},
        "weekly": {"week": week_number(client, today), "due_at": _due_at(sunday),
                   "form": form_payload(weekly, coach_first, photos=photo_week(client, today), client=client),
                   "photos_due": next_photos_due(client, today),
                   "sent": {**this_week, **full_row(Submission.objects.get(id=this_week["id"]), request)}
                   if this_week else None,
                   "last_weight": float(prev_weekly_w) if prev_weekly_w is not None else None},
        "tab": tab, "history": rows, "has_more": more, "history_total": totals,
        "next_before": rows[-1]["date"] if rows and more else None,
    }
