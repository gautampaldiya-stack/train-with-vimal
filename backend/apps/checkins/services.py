from datetime import timedelta
from decimal import Decimal, InvalidOperation

from django.db import transaction
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from apps.activity.services import log as activity_log
from apps.notifications.services import notify, send_template

from .models import (
    CHOICE_TYPES,
    Answer,
    FormRequest,
    MEASURE_KEYS,
    FormType,
    Measurement,
    PhotoSet,
    ProgressPhoto,
    QuestionType,
    Submission,
    WeightLog,
)

SCALE_HOURS = {"5 h": 5, "6 h": 6, "7 h": 7, "8 h": 8, "9 h": 9}
DEFAULT_SLOTS = ["Front", "Side", "Back"]


def photo_slots(q):
    """The photos a photo question asks for, by name: its options ("Meal", "Label"…), else Front, Side, Back."""
    return list(q.options or DEFAULT_SLOTS)


def slot_key(label):
    return " ".join(str(label).split()).lower()


def _clean_value(q, v):
    """Validate one answer against its question type. Returns the stored value (or None)."""
    if v in (None, "", []):
        return None
    t = q.type
    if t in (QuestionType.SHORT, QuestionType.LONG):
        v = str(v).strip()
        limit = 300 if t == QuestionType.SHORT else 3000
        if len(v) > limit:
            raise ValidationError({str(q.id): [f"Keep it under {limit} characters."]})
        return v
    if t == QuestionType.NUMBER:
        try:
            n = Decimal(str(v).replace(",", "."))
        except InvalidOperation:
            raise ValidationError({str(q.id): ["Enter a number."]})
        if q.metric == "weight" and not 20 <= n <= 400:
            raise ValidationError({str(q.id): ["Enter your weight in kg."]})
        if q.metric in MEASURE_KEYS and not ((3 <= n <= 70) if q.metric == "body_fat" else (10 <= n <= 300)):
            raise ValidationError({str(q.id): ["Check this number."]})
        return float(n)
    if t == QuestionType.SCALE:
        try:
            n = int(v)
        except (TypeError, ValueError):
            raise ValidationError({str(q.id): ["Pick 1 to 5."]})
        if not 1 <= n <= 5:
            raise ValidationError({str(q.id): ["Pick 1 to 5."]})
        return n
    if t == QuestionType.YES_NO:
        if isinstance(v, bool):
            return v
        if str(v).lower() in ("yes", "true", "1"):
            return True
        if str(v).lower() in ("no", "false", "0"):
            return False
        raise ValidationError({str(q.id): ["Answer yes or no."]})
    if t in CHOICE_TYPES:
        values = v if isinstance(v, list) else [v]
        if t != QuestionType.MULTIPLE and len(values) > 1:
            raise ValidationError({str(q.id): ["Pick one."]})
        out = []
        for x in values:
            x = str(x).strip()
            if x in q.options:
                out.append(x)
            elif q.allow_other and x.lower().startswith("other:") and len(x) <= 200:
                out.append(x)
            else:
                raise ValidationError({str(q.id): ["Pick one of the options."]})
        return out if t == QuestionType.MULTIPLE else out[0]
    return None


def _metric_value(q, v):
    if v is None or not q.metric:
        return None
    if q.metric == "sleep_hours" and q.type == QuestionType.SCALE:
        labels = q.scale_labels or ["5 h", "6 h", "7 h", "8 h", "9 h"]
        return SCALE_HOURS.get(labels[v - 1], v + 4)
    if q.metric == "sleep_hours" and q.type in CHOICE_TYPES:  # "6.5 h" → 6.5
        try:
            return float(str(v).split()[0])
        except ValueError:
            return None
    return v


def _sunday(d):
    return d + timedelta(days=6 - d.weekday())


def photo_week(client, day):
    """True when the weekly check-in of `day`'s week asks for photos: no set yet, or the last set before this week
    is at least the coach's N weeks old (ClientProfile.photo_every_weeks, default 2)."""
    monday = day - timedelta(days=day.weekday())
    last = (PhotoSet.objects.filter(client=client, photos__isnull=False, date__lt=monday)
            .order_by("-date").values_list("date", flat=True).first())
    if last is None:
        return True
    n = client.client_profile.photo_every_weeks or 1
    return _sunday(day) >= _sunday(last + timedelta(weeks=n))


def next_photos_due(client, today=None):
    """The Sunday the next photo set is due (Progress "Next set due", Photos page)."""
    today = today or timezone.localdate()
    last = (PhotoSet.objects.filter(client=client, photos__isnull=False, date__lte=today)
            .order_by("-date").values_list("date", flat=True).first())
    n = client.client_profile.photo_every_weeks or 1
    return _sunday(max(last + timedelta(weeks=n), today) if last else today)


def measure_entry(client, day=None):
    """Measurements are one entry per period (the photo cadence, N weeks; Gautam 2026-10-16): the entry whose
    period still covers `day`, else None. Logging again in that period changes this entry, never adds one."""
    day = day or timezone.localdate()
    n = client.client_profile.photo_every_weeks or 1
    last = Measurement.objects.filter(client=client, date__lte=day).order_by("-date").first()
    if last and _monday(day) < _monday(last.date) + timedelta(weeks=n):
        return last
    return None


def next_measure_due(client, today=None):
    """The Sunday the next measurements are due: N weeks after the current entry's week, else this Sunday."""
    today = today or timezone.localdate()
    open_ = measure_entry(client, today)
    n = client.client_profile.photo_every_weeks or 1
    return _sunday(_monday(open_.date) + timedelta(weeks=n)) if open_ else _sunday(today)


def _monday(d):
    return d - timedelta(days=d.weekday())


def week_number(client, day):
    from apps.clients.metrics import active_program

    pa = active_program(client, day)
    if pa:
        return (day - pa.start_date).days // 7 + 1
    start = client.client_profile.start_date or client.date_joined.date()
    return max(1, (day - start).days // 7 + 1)


@transaction.atomic
def submit(client, form, answers, files=None, *, request_obj=None, submission=None, note="", day=None):
    """Create (or, with `submission`, replace) a filled form. `answers` = {question_id: value},
    `files` = {question_id: [uploaded files]} for photo questions."""
    files = files or {}
    questions = list(form.questions.filter(is_removed=False))
    when = day or (submission.date if submission is not None else timezone.localdate())
    # Off weeks of "photos every N weeks" do not ask for photos, so the photo question is not required then.
    no_photos = form.type == "weekly" and not photo_week(client, when)
    cleaned, metrics = {}, {}
    # The "Body measurements" step of photo weeks (client_page.MEASURES_Q): {key: number}, all optional.
    taken_in = answers.get("-1", answers.get(-1)) if isinstance(answers, dict) else None
    if taken_in:
        if not isinstance(taken_in, dict):
            raise ValidationError({"-1": ["Send the measurements as {name: number}."]})
        for k, n in taken_in.items():
            if n in (None, ""):
                continue
            try:
                n = round(float(n), 1)
            except (TypeError, ValueError):
                raise ValidationError({"-1": [f"{k}: enter a number."]}) from None
            if k not in MEASURE_KEYS or not ((3 <= n <= 70) if k == "body_fat" else (10 <= n <= 300)):
                raise ValidationError({"-1": [f"{k}: that number looks off. Check it and try again."]})
            metrics[k] = n
    for q in questions:
        v = _clean_value(q, answers.get(str(q.id), answers.get(q.id)))
        has_photo = bool(files.get(str(q.id)))
        keep_photo = submission is not None and q.type == QuestionType.PHOTO and \
            submission.answers.filter(question=q).exclude(photo="").exists()
        skip = no_photos and q.type == QuestionType.PHOTO
        if q.required and v is None and not has_photo and not keep_photo and not skip:
            raise ValidationError({str(q.id): ["This question needs an answer."]})
        cleaned[q.id] = v
        mv = _metric_value(q, v)
        if mv is not None:
            metrics[q.metric] = mv
    if note:
        metrics["note"] = note[:200]
    today = day or timezone.localdate()
    is_new = submission is None
    if is_new:
        submission = Submission.objects.create(
            form=form, form_type=form.type, client=client, request=request_obj, date=today,
            week_number=week_number(client, today) if form.type == FormType.WEEKLY else None, metrics=metrics)
    else:
        submission.metrics = metrics
        submission.edited_at = timezone.now()
        submission.save(update_fields=["metrics", "edited_at", "updated_at"])
        submission.answers.exclude(question__type=QuestionType.PHOTO).delete()
    Answer.objects.bulk_create([Answer(submission=submission, question_id=qid, value=v)
                                for qid, v in cleaned.items() if v is not None])
    photo_set = None
    for q in questions:
        slots = photo_slots(q)
        keys = [slot_key(x) for x in slots]
        for n, f in enumerate(files.get(str(q.id), [])[:len(slots)]):
            if f.size > 10 * 1024 * 1024:
                raise ValidationError({str(q.id): ["Photos can be up to 10 MB."]})
            key = slot_key(getattr(f, "pose", None) or keys[n])
            if key not in keys:
                raise ValidationError({str(q.id): [f"This question asks for: {', '.join(slots)}."]})
            label = slots[keys.index(key)]
            submission.answers.filter(question=q, value=label).exclude(photo="").delete()  # a new photo for that slot
            Answer.objects.create(submission=submission, question=q, photo=f, value=label,
                                  private=not client.share_photos)
            if photo_set is None:
                label = f"Week {submission.week_number} check-in" if submission.week_number else form.name
                photo_set, _ = PhotoSet.objects.get_or_create(
                    client=client, submission=submission,
                    defaults={"label": label, "date": submission.date, "weight_kg": metrics.get("weight")})
            # Front, side and back also go on the Progress page, by pose.
            if key in ProgressPhoto.Pose.values:
                ProgressPhoto.objects.filter(photo_set=photo_set, pose=key).delete()
                ProgressPhoto.objects.create(photo_set=photo_set, pose=key, image=f, private=not client.share_photos)
    # Measurement answers (a question whose metric is waist, hips, …) also go on the Progress page.
    taken = {k: metrics[k] for k in MEASURE_KEYS if metrics.get(k) is not None}
    if taken:
        open_ = measure_entry(client, submission.date)
        save_measures(client, open_.date if open_ else submission.date, taken)
    if "weight" in metrics:
        WeightLog.objects.update_or_create(client=client, date=submission.date,
                                           defaults={"weight_kg": Decimal(str(metrics["weight"])),
                                                     "source": "checkin"})
        cp = client.client_profile
        cp.current_weight_kg = Decimal(str(metrics["weight"]))
        cp.save(update_fields=["current_weight_kg"])
    if request_obj and not request_obj.filled_at:
        request_obj.filled_at = timezone.now()
        request_obj.save(update_fields=["filled_at"])
    else:
        FormRequest.objects.filter(client=client, form=form, filled_at__isnull=True).update(filled_at=timezone.now())
    if is_new:
        _after_submit(client, submission)
    return submission


def _after_submit(client, sub):
    from apps.automations.engine import fire_event, response_received

    activity_log(f"sent {sub.form.name}", "checkin", actor=client, target=sub, target_label=sub.form.name,
                 client=client)
    transaction.on_commit(lambda: response_received(client))
    transaction.on_commit(lambda: fire_event("form_sent", client, dedupe=f"sub:{sub.id}",
                                             context={"form": str(sub.form_id)}))
    target = client.client_profile.target_weight_kg
    w = sub.metrics.get("weight")
    if target and w is not None:
        cp = client.client_profile
        start = cp.start_weight_kg or Decimal(str(w))
        losing = start >= target
        reached = Decimal(str(w)) <= target if losing else Decimal(str(w)) >= target
        if reached:
            transaction.on_commit(lambda: fire_event("goal_weight", client, dedupe="goal_weight"))
    trainer = client.client_profile.trainer
    if trainer and sub.form_type in (FormType.WEEKLY, FormType.DAILY, FormType.SURVEY):
        if sub.form_type == FormType.DAILY:
            # Daily pulses are many: only the trainer's bell (and the toast while the app is open), no push or
            # email, and never the admin. Off with Me → Notifications → New check-in, like the weekly one.
            from apps.notifications.models import Channel, StaffNotificationPreference
            from apps.notifications.services import notify

            from .serializers import summary_line

            p = StaffNotificationPreference.objects.filter(user=trainer).first()
            if p is None or p.new_checkin:
                notify(trainer, "checkin_submitted", f"{client.full_name} sent their daily check-in",
                       summary_line(sub), actor=client, channels=[Channel.IN_APP],
                       data={"route": f"/checkins/{sub.id}", "submission": str(sub.id)})
        else:
            from apps.notifications.staff import team_alert

            label = f"week {sub.week_number} check-in" if sub.week_number else sub.form.name
            team_alert("checkin_submitted", client, f"{client.full_name} sent their {label}",
                       notify_event="checkin_submitted", actor=client, trainer=trainer, pref="new_checkin",
                       data={"route": f"/checkins/{sub.id}", "submission": str(sub.id)})


@transaction.atomic
def review(sub, *, actor, reply=""):
    sub.reviewed_at = timezone.now()
    sub.reviewed_by = actor
    sub.reply = reply or ""
    sub.save(update_fields=["reviewed_at", "reviewed_by", "reply", "updated_at"])
    activity_log("reviewed a check-in", "checkin", actor=actor, target=sub.client, target_label=sub.form.name,
                 client=sub.client)
    if reply:
        from apps.notifications.models import ReminderPreference

        pref = ReminderPreference.objects.filter(user=sub.client).first()
        if pref is None or pref.trainer_reply:
            send_template(sub.client, "coach-feedback", actor=actor,
                          data={"route": f"/checkins/{sub.id}", "submission": str(sub.id), "reply": reply[:300]})
    return sub


def unreview(sub):
    sub.reviewed_at = None
    sub.reviewed_by = None
    sub.save(update_fields=["reviewed_at", "reviewed_by", "updated_at"])
    return sub


def form_route(req):
    """Where a form notification opens in the client app: its own card's page, or the form to fill."""
    t = req.form.type
    return "/checkins/weekly" if t == "weekly" else "/checkins/daily" if t == "daily" else f"/checkins/forms/{req.id}"


def send_form(client, form, *, actor=None, automation_run=None, due_at=None, channels=None):
    """Client profile → Send a form (or an automation step)."""
    req = FormRequest.objects.create(form=form, client=client, sent_by=actor, automation_run=automation_run,
                                     due_at=due_at)
    notify(client, "form_request", f"{form.name}", "Your coach sent you a form. It takes a few minutes.",
           actor=actor, channels=channels, data={"route": form_route(req), "request": str(req.id)})
    activity_log(f"sent {form.name}", "checkin", actor=actor, target=client, target_label=form.name, client=client)
    return req


def streak(client, form_type="daily"):
    """'6-day streak' — consecutive days up to today with a submission of this type."""
    days = set(Submission.objects.filter(client=client, form_type=form_type)
               .order_by("-date").values_list("date", flat=True)[:400])
    d = timezone.localdate()
    if d not in days:
        d = d - timezone.timedelta(days=1)
    n = 0
    while d in days:
        n += 1
        d -= timezone.timedelta(days=1)
    return n


def save_photo(client, *, pose, image, label=None, day=None):
    day = day or timezone.localdate()
    ps, _ = PhotoSet.objects.get_or_create(client=client, date=day, submission=None,
                                           defaults={"label": label or "Progress photos"})
    if ps.weight_kg is None:
        w = WeightLog.objects.filter(client=client, date__lte=day).order_by("-date").first()
        if w:
            ps.weight_kg = w.weight_kg
            ps.save(update_fields=["weight_kg"])
    ProgressPhoto.objects.filter(photo_set=ps, pose=pose).delete()
    return ProgressPhoto.objects.create(photo_set=ps, pose=pose, image=image, private=not client.share_photos)


def save_measures(client, day, values):
    """Merge {key: number | None} into the day's measurements. None takes a key off; an empty day is deleted."""
    m = Measurement.objects.filter(client=client, date=day).first()
    v = dict(m.values) if m else {}
    for k, n in values.items():
        if n is None:
            v.pop(k, None)
        else:
            v[k] = float(n)
    if not v:
        if m:
            m.delete()
        return None
    if m:
        m.values = v
        m.save(update_fields=["values"])
        return m
    return Measurement.objects.create(client=client, date=day, values=v)


def _log_plain_body(client, day, what, after):
    """Coach's feed (client profile → Activity, kind Body): "Riya logged body weight · 72.3 kg → 71.6 kg"
    (from the weigh-in before), or "Riya added measurements · Waist 84 cm, Hips 101 cm"."""
    from .models import MEASURES

    if "weight" in after:
        prev = (WeightLog.objects.filter(client=client, date__lt=day).order_by("-date")
                .values_list("weight_kg", flat=True).first())
        now = f"{float(after['weight']):g} kg"
        activity_log("logged body weight", "body", actor=client, client=client, target_label=now,
                     change=(f"{float(prev):g} kg", now) if prev is not None else None)
        return
    names = {k: (lbl, u) for k, lbl, u in MEASURES}
    parts = [f"{names[k][0]} {float(v):g} {names[k][1]}" for k, v in after.items() if k in names and v is not None]
    if parts:
        activity_log("added measurements", "body", actor=client, client=client,
                     meta={"note": ", ".join(parts[:3]) + (f" +{len(parts) - 3}" if len(parts) > 3 else "")})


def log_body_change(client, day, what, before, after):
    """A weigh-in or measurement for a past day, or a change to one already logged, goes in My activity
    (and the coach's feed) as its own line, so an edit never hides. before / after = {key: number}."""
    from apps.common.utils import dfmt

    from .models import MEASURES

    today = timezone.localdate()
    names = {k: (lbl, u) for k, lbl, u in MEASURES} | {"weight": ("Weight", "kg")}
    changed = [k for k in after if k in before and before[k] != after[k]]
    gone = [k for k in before if k not in after]
    if not changed and not gone and day >= today:
        _log_plain_body(client, day, what, after)
        return  # a plain log for today: it already shows as "Logged …" in My activity
    on = dfmt(day, "%a, %-d %b")
    edit = bool(changed or gone)
    title = f"You {'changed' if edit else 'added'} {what} for {on}"

    def n(v):
        return f"{float(v):g}"

    rows = []
    for k in sorted(set(before) | set(after), key=lambda k: list(names).index(k) if k in names else 99):
        lbl, u = names.get(k, (k, ""))
        if k in changed:
            rows.append([lbl, f"{n(before[k])} → {n(after[k])} {u}".strip()])
        elif k in gone:
            rows.append([lbl, f"{n(before[k])} {u} → removed".strip()])
        elif k not in before:
            rows.append([lbl, f"{n(after[k])} {u}".strip()])
    if not rows:
        return
    rows.append(["For", on + (" (a past day)" if day < today else "")])
    sub = ", ".join(r[0] for r in rows[:-1][:3]) + (f" +{len(rows) - 4}" if len(rows) > 4 else "")
    activity_log(title[4:].replace("your", "their"), "body", actor=client, client=client,
                 meta={"note": sub, "mine": {"t": title, "s": sub, "rows": rows, "k": "Check-ins", "icon": "scale",
                                "color": "amber", "link": "/progress", "label": "See progress"}})
