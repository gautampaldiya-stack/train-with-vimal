"""Client app → Check-ins page (boards ClientCheckin / ClientCheckinWeb).

The weekly check-in is due on the client's schedule day (`schedule.py`, default Sunday 6:00 pm), open that day
and 2 more, then Missed. A daily check-in belongs to its own day and stays open until the end of the next day
(last night's sleep is known only the next morning, like Food); after that it is Missed. History is paged with
`before` (a date), newest first.
"""
from datetime import datetime, time, timedelta

from django.utils import timezone

from .defaults import CHIPS
from .models import Form, QuestionType, Submission, WeightLog

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


MEASURES_Q = -1  # older app builds: the auto "Body measurements" step; its answer is {key: number}


def measure_rows(client, keys=None, settings=None):
    """The rows of a "Body measurements" question: [keys] the coach picked, else the client's tracked ones (D-24).
    Each row starts from the last value logged."""
    from .models import DEFAULT_MEASURES, MEASURES, Measurement

    keys = keys or (client.client_profile.measure_keys if client else None) or DEFAULT_MEASURES
    last = {}
    for m in (Measurement.objects.filter(client=client).order_by("-date")[:60] if client else []):
        for k, v in m.values.items():
            last.setdefault(k, (v, m.date))
    st = settings or {}
    inch, req = st.get("units") or {}, set(st.get("required") or [])

    def row(k, lbl, u):
        v, on = last.get(k, (None, None))
        if inch.get(k) == "in":  # the coach asks this one in inches; stored in cm
            u, v = "in", (round(float(v) / 2.54, 1) if v is not None else None)
        return {"key": k, "label": lbl, "unit": u, "last": v, "last_date": on, "required": k in req}

    return [row(k, lbl, u) for k, lbl, u in MEASURES if k in keys]


def last_number(client, q):
    """Quick pick starts from her last answer: a weight question from her last weigh-in, else her last answer to
    this question (or the master question it was copied from)."""
    from .models import Answer

    if q.metric == "weight":
        w = WeightLog.objects.filter(client=client).order_by("-date").values_list("weight_kg", flat=True).first()
        if w is not None:
            return float(w)
    ids = [i for i in (q.id, q.copied_from_id) if i]
    v = (Answer.objects.filter(submission__client=client, question_id__in=ids).exclude(value=None)
         .order_by("-submission__date", "-submission__created_at").values_list("value", flat=True).first())
    return float(v) if isinstance(v, (int, float)) else None


def form_payload(form, coach_first, photos=True, client=None):
    """`photos=False` on the off weeks of "photos every N weeks": the photo question is left out.
    With `client` on a photo week, a "Body measurements" step goes in just before the photos."""
    if form is None:
        return None
    from .services import measure_entry

    # A weekly "Body measurements" question goes with the photos (off weeks leave it out) and is skipped when this
    # period already has its entry (logged from Progress): one entry per period (D-25). Every question is the
    # coach's own (Probid 2026-10-31); nothing is added here.
    taken = form.type == "weekly" and client is not None and measure_entry(client) is not None
    qs = [q for q in form.questions.all() if not q.is_removed and (photos or q.type != QuestionType.PHOTO)
          and not (q.type == QuestionType.MEASURES and (taken or (form.type == "weekly" and not photos)))
          # the daily check-in is one quick page: photos and body measurements belong to the weekly one
          and not (form.type == "daily" and q.type in (QuestionType.PHOTO, QuestionType.MEASURES))]
    out = []
    for q in qs:
        row = {"id": q.id, "text": q.text, "type": q.type, "options": q.options, "scale_labels": q.scale_labels,
               "allow_other": q.allow_other, "suggestions": q.suggestions, "allow_skip": q.allow_skip,
               "settings": q.settings,
               "help_text": q.help_text.replace("{coach}", coach_first or "your coach"),
               "required": q.required, "metric": q.metric, "chip": _chip(q)}
        if q.type == QuestionType.MEASURES:
            row["measures"] = measure_rows(client, q.options, q.settings)
        if q.type == QuestionType.NUMBER and client is not None and (q.settings or {}).get("quick"):
            row["last"] = last_number(client, q)
        out.append(row)
    return {"id": str(form.id), "name": form.name, "type": form.type, "questions": out}


def _week_counts(client, monday):
    """Workouts done / planned and the share of planned meals logged, Monday to Sunday."""
    from apps.clients.metrics import active_meal_plan, active_program, planned_meals, planned_workout_days
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
        want = planned_meals(mp, monday, end)
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
    from . import schedule
    from .services import week_number

    today = timezone.localdate()
    start = _start(client)
    wd, t = schedule.slot(client)
    subs = list(Submission.objects.filter(client=client, form_type="weekly").order_by("-date", "-created_at"))
    _photo_counts(subs)
    keyed = set()
    rows = []
    for s in subs:
        due = schedule.due_for(client, s.date, wd)  # the due date it belongs to (new ones are stored on it)
        keyed.add(due)
        r = _row(s)
        r["due"] = due
        r["week_number"] = s.week_number or week_number(client, due)
        r["on_time"] = s.created_at <= schedule.due_at(client, due, t)
        rows.append(r)
    # Missed: every due date since the start whose window has closed with nothing sent.
    due = schedule.due_on_or_after(client, start, wd)
    while due + timedelta(days=schedule.OPEN_DAYS) < today:
        if due not in keyed:
            rows.append({"id": None, "kind": "missed", "date": due, "due": due,
                         "week_number": week_number(client, due), "due_at": schedule.due_at(client, due, t)})
        due += timedelta(days=7)
    rows.sort(key=lambda r: (r["date"], r.get("sent_at") or r.get("due_at")), reverse=True)
    # Weight change against the check-in before (the label says "In 2 weeks" across a gap).
    sent = [r for r in rows if r["kind"] == "sent"]
    for i, r in enumerate(sent):
        w = r["metrics"].get("weight")
        prev = next((p for p in sent[i + 1:] if p["metrics"].get("weight") is not None), None)
        if w is not None and prev is not None:
            r["change_kg"] = round(float(w) - float(prev["metrics"]["weight"]), 1)
            r["change_weeks"] = max(1, round((r["date"] - prev["date"]).days / 7))
    return rows


def daily_strip(client, today):
    """Check-ins week strip (like Food): last week and this week, each day sent or not."""
    monday = today - timedelta(days=today.weekday())
    first = monday - timedelta(days=7)
    sent = set(Submission.objects.filter(client=client, form_type="daily", date__range=(first, monday + timedelta(days=6)))
               .values_list("date", flat=True))
    start = _start(client)
    return [{"date": first + timedelta(days=i), "sent": first + timedelta(days=i) in sent,
             "before_start": first + timedelta(days=i) < start} for i in range(14)]


DAILY_OPEN_DAYS = 1  # a day's daily check-in can still be sent the next day


def daily_open_day(client, today=None):
    """The day the daily card asks about: yesterday while it is still open and not sent, else today."""
    today = today or timezone.localdate()
    y = today - timedelta(days=1)
    if y >= _start(client) and not Submission.objects.filter(client=client, form_type="daily", date=y).exists():
        return y
    return today


def daily_rows(client, form):
    today = timezone.localdate()
    start = max(_start(client), today - timedelta(days=365))
    subs = list(Submission.objects.filter(client=client, form_type="daily", date__gte=start).order_by("-date"))
    rows = [_row(s) for s in subs]
    if form is not None:
        have = {s.date for s in subs}
        d = today - timedelta(days=1 + DAILY_OPEN_DAYS)  # yesterday is still open, so not Missed yet
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
    return _live_form("weekly")


def checkins_page(client, tab="weekly", before=None, request=None, day=None):
    """`day`: the day picked in the week strip (its daily check-in); none = the open one (yesterday or today)."""
    from apps.clients.metrics import active_program

    from . import schedule
    from .services import next_photos_due, photo_week, streak, week_number

    today = timezone.localdate()
    cur = schedule.current(client, today)
    cp = client.client_profile
    coach = cp.trainer
    coach_first = coach.first_name if coach else ""
    weekly = client_weekly_form(client)
    daily = _live_form("daily")

    w_rows = weekly_rows(client)
    sent_w = [r for r in w_rows if r["kind"] == "sent"]
    due_weeks = [r for r in w_rows if r["kind"] == "missed" or r["due"] < cur["due"]]
    this_week = next((r for r in sent_w if r["due"] == cur["due"]), None)
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
            r.update(_week_counts(client, r["due"] - timedelta(days=6)))

    # the picked day (never before the start or after today), else yesterday while it is still open, else today
    day = min(max(day, _start(client)), today) if day else daily_open_day(client, today)
    d_today = Submission.objects.filter(client=client, form_type="daily", date=day).first()
    last_w = WeightLog.objects.filter(client=client, date__lt=day).order_by("-date").first()
    today_w = WeightLog.objects.filter(client=client, date=day).first()
    prev_weekly_w = next((r["metrics"]["weight"] for r in sent_w
                          if r["metrics"].get("weight") is not None and r is not this_week), None)
    pa = active_program(client, today)
    return {
        "coach": {"name": coach.full_name, "first_name": coach_first, "initials": coach.initials,
                  "avatar_color": coach.avatar_color} if coach else None,
        "program": {"name": pa.effective_program.name, "week": week_number(client, today),
                    "weeks": pa.effective_program.weeks} if pa else None,
        "stats": {"streak": streak(client, "daily"), "weekly_on_time": on_time, "weekly_due": due_total,
                  "last_change_kg": last_change},
        "daily": {"date": day, "is_yesterday": day == today - timedelta(days=1),
                  # today and yesterday can be filled / edited, older days are view-only (like Food)
                  "editable": day >= today - timedelta(days=1),
                  "strip": daily_strip(client, today), "form": form_payload(daily, coach_first),
                  "sent": full_row(d_today, request), **_habit_day(client, day),
                  "last_weight": {"date": last_w.date, "kg": float(last_w.weight_kg)} if last_w else None,
                  "today_weight": float(today_w.weight_kg) if today_w else None},
        "weekly": {"week": week_number(client, cur["due"]), "due_at": cur["due_at"], "due": cur["due"],
                   "open": cur["open"], "late": cur["late"], "closes": cur["closes"],
                   "form": form_payload(weekly, coach_first, photos=photo_week(client, cur["due"]), client=client),
                   "photos_due": next_photos_due(client, today),
                   "sent": {**this_week, **full_row(Submission.objects.get(id=this_week["id"]), request)}
                   if this_week else None,
                   "last_weight": float(prev_weekly_w) if prev_weekly_w is not None else None},
        # The setup questionnaire while it is not finished, also with 0 answered (E42).
        "onboarding": _onboarding(client),
        "tab": tab, "history": rows, "has_more": more, "history_total": totals,
        "next_before": rows[-1]["date"] if rows and more else None,
    }


# ---------- Forms the coach sent (boards ClientForm / ClientFormWeb, D-49) ----------

FORMS_SENT_DAYS = 14  # a filled form stays on the page as "Sent" for two weeks
CARD_SKIP = ("weekly", "daily")  # these have their own cards


def _minutes(n):
    m = max(1, round(n * 20 / 60))  # about 20 seconds a question
    return "about a minute" if m == 1 else f"about {m} minutes"


def _from(req, coach_first):
    if req.sent_by is not None and req.sent_by.first_name:
        return req.sent_by.first_name
    return coach_first or "Your coach"


def form_card(req, coach_first):
    qs = [q for q in req.form.questions.all() if not q.is_removed]
    n = len(qs)
    return {"id": str(req.id), "name": req.form.name, "type": req.form.type, "from": _from(req, coach_first),
            "sent_at": req.created_at, "due_at": req.due_at, "filled_at": req.filled_at,
            "question_count": n, "chips": [_chip(q) for q in qs[:5]],
            "why": f"{n} {'question' if n == 1 else 'questions'}. Takes {_minutes(n)}."}


def form_cards(client):
    """Waiting forms first (oldest due first), then the ones filled in the last two weeks."""
    from .models import FormRequest

    coach = client.client_profile.trainer
    coach_first = coach.first_name if coach else ""
    since = timezone.now() - timedelta(days=FORMS_SENT_DAYS)
    base = (FormRequest.objects.filter(client=client).exclude(form__type__in=CARD_SKIP)
            .select_related("form", "sent_by").prefetch_related("form__questions"))
    waiting = base.filter(filled_at__isnull=True).order_by("due_at", "created_at")
    done = base.filter(filled_at__gte=since).order_by("-filled_at")
    return [form_card(r, coach_first) for r in list(waiting) + list(done)]


def form_request(client, req, request=None):
    """One form to fill (or what was sent): the card, its questions and, once filled, the answers and photos."""
    coach = client.client_profile.trainer
    coach_first = coach.first_name if coach else ""
    out = form_card(req, coach_first)
    out["form"] = form_payload(req.form, _from(req, coach_first))
    sub = Submission.objects.filter(request=req).order_by("-created_at").first() if req.filled_at else None
    out["submission"] = None if sub is None else {
        "id": str(sub.id), "sent_at": sub.created_at,
        "answers": {str(a.question_id): a.value for a in sub.answers.all() if not a.photo},
        "photos": answer_photos(sub, request)}
    return out


def _live_form(form_type):
    from apps.checkins.library import live_form

    return live_form(form_type)


def _onboarding(client):
    from apps.clients.onboarding import status

    st = status(client)
    return None if st["complete"] else st
