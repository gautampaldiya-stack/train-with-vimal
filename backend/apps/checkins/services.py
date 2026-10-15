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
    FormType,
    PhotoSet,
    ProgressPhoto,
    QuestionType,
    Submission,
    WeightLog,
)

SCALE_HOURS = {"5 h": 5, "6 h": 6, "7 h": 7, "8 h": 8, "9 h": 9}


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
    cleaned, metrics = {}, {}
    for q in questions:
        v = _clean_value(q, answers.get(str(q.id), answers.get(q.id)))
        has_photo = bool(files.get(str(q.id)))
        keep_photo = submission is not None and q.type == QuestionType.PHOTO and \
            submission.answers.filter(question=q).exclude(photo="").exists()
        if q.required and v is None and not has_photo and not keep_photo:
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
        for n, f in enumerate(files.get(str(q.id), [])[:3]):
            if f.size > 10 * 1024 * 1024:
                raise ValidationError({str(q.id): ["Photos can be up to 10 MB."]})
            Answer.objects.create(submission=submission, question=q, photo=f)
            if photo_set is None:
                label = f"Week {submission.week_number} check-in" if submission.week_number else form.name
                photo_set, _ = PhotoSet.objects.get_or_create(
                    client=client, submission=submission,
                    defaults={"label": label, "date": submission.date, "weight_kg": metrics.get("weight")})
            # The same photo on the Progress page, by pose (Front, Side, Back).
            pose = getattr(f, "pose", None) or ProgressPhoto.Pose.values[n]
            ProgressPhoto.objects.filter(photo_set=photo_set, pose=pose).delete()
            ProgressPhoto.objects.create(photo_set=photo_set, pose=pose, image=f)
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
        from apps.notifications.models import StaffNotificationPreference

        pref = StaffNotificationPreference.objects.filter(user=trainer).first()
        if sub.form_type == FormType.DAILY:
            # Daily pulses are many: no push, only a live refresh of the review queue.
            from apps.notifications.realtime import send_to_user

            transaction.on_commit(lambda: send_to_user(trainer.id, "checkin_submitted",
                                                       {"id": str(sub.id), "client": str(client.id)}))
        elif pref is None or pref.new_checkin:
            label = f"week {sub.week_number} check-in" if sub.week_number else sub.form.name
            notify(trainer, "checkin_submitted", f"{client.full_name} sent their {label}",
                   "", actor=client, data={"route": f"/checkins/{sub.id}", "submission": str(sub.id)})


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


def send_form(client, form, *, actor=None, automation_run=None, due_at=None, channels=None):
    """Client profile → Send a form (or an automation step)."""
    req = FormRequest.objects.create(form=form, client=client, sent_by=actor, automation_run=automation_run,
                                     due_at=due_at)
    notify(client, "form_request", f"{form.name}", "Your coach sent you a form. It takes a few minutes.",
           actor=actor, channels=channels, data={"route": f"/forms/{req.id}", "request": str(req.id)})
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
    return ProgressPhoto.objects.create(photo_set=ps, pose=pose, image=image)
