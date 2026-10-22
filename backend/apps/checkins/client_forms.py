"""Client profile → Forms tab (boards TrainerClientProfile / …Mobile).

The list on the left: the onboarding questionnaire (her setup answers), every form she was sent or filled
(waiver, PAR-Q, feedback…), her weekly check-in (recurring) and any form sent to her on a repeat. The card on the
right shows the selected one: answers by section, or the questions with what was changed for her.

Changing a form "for Riya" never touches the library form: the first edit makes her own copy
(`Form.status = client`, `master` = the library form, each question keeps `copied_from`). "Reset to master" drops
the copy, "Stop sending" turns her weekly check-in off (or ends a repeat / withdraws a form she has not answered)."""

from datetime import datetime, time, timedelta

from django.db import transaction
from django.db.models import Q
from django.shortcuts import get_object_or_404
from django.utils import timezone
from django.utils.dateparse import parse_date, parse_time
from rest_framework import serializers
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.activity.services import log as activity_log
from apps.common.permissions import IsStaff
from apps.common.utils import dfmt
from apps.notifications.services import notify

from . import services
from .models import Answer, Form, FormRequest, FormSchedule, FormType, Question, QuestionType, Submission
from .serializers import QuestionSerializer

TYPE_LABEL = {
    QuestionType.SHORT: "Text", QuestionType.LONG: "Text", QuestionType.NUMBER: "Number",
    QuestionType.SINGLE: "One choice", QuestionType.MULTIPLE: "Choices", QuestionType.DROPDOWN: "Dropdown",
    QuestionType.SCALE: "Scale 1–5", QuestionType.YES_NO: "Yes / no", QuestionType.PHOTO: "Photo",
}
FORM_SUB = {"weekly": "Weekly check-in · weight, energy, meals", "survey": "Survey or feedback",
            "waiver": "Waiver or consent", "onboarding": "Onboarding questions", "daily": "Daily check-in"}
BY = {"push": (["in_app", "push"], "Push"), "push_whatsapp": (["in_app", "push", "whatsapp"], "Push + WhatsApp"),
      "push_email": (["in_app", "push", "email"], "Push + email")}
DAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
WEEKLY_DUE = "every Sunday, 6:00 pm"  # the client's Check-ins page: the weekly check-in is due Sunday 6 pm


def _first(u):
    return (u.first_name or u.full_name.split(" ")[0]) if u else ""


def _client(user, pk):
    from apps.clients.services import get_visible_client

    try:
        return get_visible_client(user, pk)
    except Exception:
        from django.http import Http404

        raise Http404


def _d(v, fmt="%-d %b"):
    return dfmt(timezone.localtime(v) if isinstance(v, datetime) else v, fmt)


def _clock(t):
    return dfmt(t, "%-I:%M %p").lower().replace(":00 ", ":00 ")


# ------------------------------------------------------------------ copies


def own_weekly(client):
    return (Form.objects.filter(type="weekly", status=Form.Status.CLIENT, client=client)
            .prefetch_related("questions").order_by("-created_at").first())


def master_weekly():
    return Form.objects.filter(type="weekly", status="published").prefetch_related("questions").first()


def master_of(form):
    if form is None:
        return None
    if form.status != Form.Status.CLIENT:
        return form
    return Form.all_objects.filter(id=form.master_id).first() if form.master_id else None


def live_questions(form):
    return [q for q in form.questions.all() if not q.is_removed] if form else []


def changes(form):
    """What her copy changed against the master: per question id a short line, and the summary."""
    master = master_of(form)
    if form is None or form.status != Form.Status.CLIENT or master is None:
        return {}, ("new form" if form is not None and form.status == Form.Status.CLIENT else "")
    per, added, changed = {}, 0, 0
    src = {q.id: q for q in master.questions.all()}
    kept = set()
    for q in live_questions(form):
        m = src.get(q.copied_from_id)
        if m is None:
            per[q.id] = "added"
            added += 1
            continue
        kept.add(m.id)
        if q.text != m.text:
            per[q.id] = f"Was: {m.text}"
        elif q.required != m.required:
            per[q.id] = "Was: required" if m.required else "Was: optional"
        elif q.type != m.type:
            per[q.id] = f"Was: {TYPE_LABEL.get(m.type, m.type).lower()}"
        else:
            continue
        changed += 1
    removed = len([m for m in live_questions(master) if m.id not in kept])
    parts = [f"{n} {w}" for n, w in ((added, "added"), (changed, "changed"), (removed, "removed")) if n]
    if parts:  # "1 question added, 1 changed"
        n = int(parts[0].split(" ")[0])
        parts[0] = parts[0].replace(" ", f" question{'s' if n != 1 else ''} ", 1)
    return per, ", ".join(parts) if parts else "no changes"


def _copy(master, client, actor, name=None):
    f = Form.objects.create(name=(name or master.name)[:120], type=master.type, status=Form.Status.CLIENT,
                            is_parq=master.is_parq, client=client, master=master, created_by=actor)
    return f


def _copy_questions(src, dst):
    Question.objects.bulk_create([
        Question(form=dst, order=q.order, text=q.text, type=q.type, options=q.options, scale_labels=q.scale_labels,
                 allow_other=q.allow_other, help_text=q.help_text, required=q.required, metric=q.metric,
                 profile_key=q.profile_key, copied_from_id=q.copied_from_id if src.status == Form.Status.CLIENT else q.id)
        for q in live_questions(src)])


def save_questions(form, items, master=None):
    """The editor's whole list. Ids of her copy update in place; a master id makes a copied question; no id = new.
    Answered questions taken off the list stay readable (as in the forms library builder)."""
    s = QuestionsIn(data={"questions": items})
    s.is_valid(raise_exception=True)
    mine = {q.id: q for q in form.questions.all()}
    src = {q.id: q for q in master.questions.all()} if master else {}
    keep = []
    for i, qd in enumerate(s.validated_data["questions"]):
        qid = qd.get("id")
        q = mine.get(qid)
        if q is None:
            m = src.get(qid)
            q = Question(form=form, copied_from=m)
            if m is not None:  # fields the editor does not show come from the master question
                for k in ("options", "scale_labels", "allow_other", "help_text", "metric", "profile_key"):
                    setattr(q, k, getattr(m, k))
        for k, v in qd.items():
            if k != "id":
                setattr(q, k, v)
        q.order = i
        q.is_removed = False
        q.save()
        keep.append(q.id)
    gone = form.questions.exclude(id__in=keep)
    answered = set(Answer.objects.filter(question__in=gone).values_list("question_id", flat=True))
    gone.exclude(id__in=answered).delete()
    Question.objects.filter(id__in=answered).update(is_removed=True, order=999)
    form.save(update_fields=["updated_at"])


class QuestionIn(QuestionSerializer):
    def validate(self, attrs):
        attrs = super().validate(attrs)
        attrs.pop("metric", None)  # set by the master only
        return attrs


class QuestionsIn(serializers.Serializer):
    questions = QuestionIn(many=True)

    def validate_questions(self, v):
        if not v:
            raise serializers.ValidationError("Keep at least one question.")
        if len(v) > 60:
            raise serializers.ValidationError("Up to 60 questions.")
        return v


# ------------------------------------------------------------------ schedules


def _at(day, t):
    return timezone.make_aware(datetime.combine(day, t))


def next_run(s, after=None):
    """The next send of a repeat after `after` (now by default), or None when it is over."""
    now = after or timezone.now()
    today = timezone.localtime(now).date()
    t = s.time if isinstance(s.time, time) else parse_time(str(s.time))
    if s.repeat == FormSchedule.Repeat.WEEK:
        d = today + timedelta(days=(s.weekday - today.weekday()) % 7)
        when = _at(d, t)
        if when <= now:
            when = _at(d + timedelta(days=7), t)
    elif s.repeat == FormSchedule.Repeat.MONTH:
        y, m = today.year, today.month
        for _ in range(3):
            day = min(s.month_day, 28)
            when = _at(datetime(y, m, day).date(), t)
            if when > now:
                break
            y, m = (y + 1, 1) if m == 12 else (y, m + 1)
    else:
        return None
    if s.until and timezone.localtime(when).date() > s.until:
        return None
    return when


def schedule_label(s):
    if s.repeat == FormSchedule.Repeat.WEEK:
        return f"Every {DAYS[s.weekday]}"
    if s.repeat == FormSchedule.Repeat.MONTH:
        n = s.month_day
        suf = "th" if 10 <= n % 100 <= 20 else {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")
        return f"Every month · {n}{suf}"
    return f"Once · {_d(s.next_at, '%a, %-d %b')}" if s.next_at else "Once"


def _by_label(channels):
    for _, (ch, label) in BY.items():
        if set(ch) == set(channels or []):
            return label
    return "Push"


def send(client, form, actor, *, channels=None, answer_days=2, auto_remind=True, schedule=None):
    req = services.send_form(client, form, actor=actor, channels=channels,
                             due_at=timezone.now() + timedelta(days=answer_days) if answer_days else None)
    FormRequest.objects.filter(id=req.id).update(auto_remind=auto_remind, schedule=schedule)
    return req


def run_schedules(now=None):
    """Beat task body: send what is due, and the one reminder 24 h after a form went out unanswered."""
    now = now or timezone.now()
    sent = 0
    for s in FormSchedule.objects.filter(active=True, next_at__lte=now).select_related("client", "form"):
        with transaction.atomic():
            s = FormSchedule.objects.select_for_update().get(id=s.id)
            if not s.active or s.next_at is None or s.next_at > now:
                continue
            send(s.client, s.form, s.created_by, channels=s.channels or None, answer_days=s.answer_days,
                 auto_remind=s.auto_remind, schedule=s)
            s.next_at = next_run(s, now)
            s.active = s.next_at is not None
            s.save(update_fields=["next_at", "active", "updated_at"])
            sent += 1
    due = FormRequest.objects.filter(auto_remind=True, filled_at__isnull=True, reminded_at__isnull=True,
                                     created_at__lte=now - timedelta(hours=24)).select_related("form", "client")
    for r in due:
        remind(r)
    return sent


def remind(req):
    notify(req.client, "form_reminder", req.form.name, "A quick reminder: your coach is waiting for this form.",
           data={"route": services.form_route(req), "request": str(req.id)})
    req.reminded_at = timezone.now()
    req.save(update_fields=["reminded_at", "updated_at"])


# ------------------------------------------------------------------ the list


def _answer(a):
    v = a.value
    t = a.question.type
    if a.photo:
        return "Photo"
    if v is None or v == "" or v == []:
        return "—"
    if t == QuestionType.YES_NO or isinstance(v, bool):
        return "Yes" if v in (True, "yes", "Yes", 1, "true") else "No"
    if t == QuestionType.SCALE:
        return f"{v} of 5"
    if isinstance(v, list):
        return ", ".join(str(x) for x in v)
    return str(v)


def answers_of(sub):
    rows = [{"q": a.question.text, "a": _answer(a)} for a in
            sorted(sub.answers.all(), key=lambda a: (a.question.order, a.question_id))]
    return [{"title": "Answers", "rows": rows}]


def _status(req_or_sub, form):
    if form.type == FormType.WAIVER:
        return "signed", "Signed"
    return "done", "Done"


def _start_photos(client, request):
    """The onboarding's start photos (front / side / back) shown with the completed questionnaire's answers."""
    from apps.clients.onboarding import start_photos

    got = start_photos(client, request)
    return [{"pose": pose, "label": label, "url": got[pose]}
            for pose, label in (("front", "Front"), ("side", "Side"), ("back", "Back")) if got.get(pose)]


def rows(client, request=None):
    """Left list, newest first after the onboarding questionnaire and the weekly check-in."""
    cp = client.client_profile
    out = []
    steps = len(cp.client_steps_done)
    if cp.onboarding:
        from apps.clients.models import CLIENT_ONBOARDING_STEPS
        from apps.clients.onboarding import answer_sections

        total = len(CLIENT_ONBOARDING_STEPS)
        done = steps >= total
        filled = cp.terms_agreed_at or cp.created_at
        # The answers are the profile fields (Edit profile changes them), in the admin's question words.
        out.append({"key": "onboarding", "kind": "onboarding", "name": "Onboarding questionnaire",
                    "status": "done" if done else "waiting", "status_label": "Done" if done else "Waiting",
                    "sub": (f"Filled {_d(filled)} · {steps} parts" if done else f"{steps} of {total} parts filled"),
                    "icon": "form", "filled_at": filled if done else None, "sections": answer_sections(client),
                    "photos": _start_photos(client, request) if done else []})
    one_off = Q(schedule__isnull=True) | Q(schedule__repeat=FormSchedule.Repeat.ONCE)
    reqs = list(FormRequest.objects.filter(one_off, client=client).select_related("form")
                .prefetch_related("form__questions").order_by("-created_at")[:60])
    seen_subs = set()
    for r in reqs:
        sub = Submission.objects.filter(request=r).order_by("-created_at").first() if r.filled_at else None
        if sub:
            seen_subs.add(sub.id)
        if r.filled_at:
            st, label = _status(r, r.form)
            line = f"{'Signed' if st == 'signed' else 'Filled'} {_d(r.filled_at)}"
        else:
            st, label = "waiting", "Waiting"
            _, summary = changes(r.form)
            line = f"Sent {_d(r.created_at)} · " + (
                "same as master" if summary in ("", "no changes") else
                ("new form for " + _first(client) if summary == "new form" else f"edited for {_first(client)}"))
        out.append({"key": f"req:{r.id}", "kind": "request", "name": r.form.name, "status": st,
                    "status_label": label, "sub": line, "icon": "form", "at": r.created_at})
    # Filled without being sent from here (waiver or PAR-Q at sign-up, feedback from an automation…).
    for s in (Submission.objects.filter(client=client, request__isnull=True)
              .exclude(form_type__in=["weekly", "daily"]).select_related("form").order_by("-created_at")[:30]):
        if s.id in seen_subs:
            continue
        st, label = _status(s, s.form)
        out.append({"key": f"sub:{s.id}", "kind": "submission", "name": s.form.name, "status": st,
                    "status_label": label, "sub": f"{'Signed' if st == 'signed' else 'Filled'} {_d(s.created_at)}",
                    "icon": "form", "at": s.created_at})
    weekly = own_weekly(client) or master_weekly()
    if weekly is not None:
        on = weekly.sending
        _, summary = changes(weekly)
        edited = summary not in ("", "no changes")
        out.append({"key": "weekly", "kind": "weekly", "name": weekly.name,
                    "status": "recurring" if on else "stopped", "status_label": "Recurring" if on else "Stopped",
                    "sub": ("Every Sunday" if on else "Stopped") + (
                        f" · edited for {_first(client)}" if edited else " · same as master"),
                    "icon": "calendar"})
    for s in (FormSchedule.objects.filter(client=client).exclude(repeat=FormSchedule.Repeat.ONCE, active=False)
              .select_related("form").order_by("-created_at")):
        if s.repeat == FormSchedule.Repeat.ONCE:
            st, label = "scheduled", "Scheduled"
        else:
            st, label = ("recurring", "Recurring") if s.active else ("stopped", "Stopped")
        out.append({"key": f"sched:{s.id}", "kind": "schedule", "name": s.form.name, "status": st,
                    "status_label": label, "sub": schedule_label(s) if s.active else "Stopped",
                    "icon": "calendar", "at": s.created_at})
    head = [r for r in out if r["kind"] in ("onboarding", "weekly")]
    rest = sorted([r for r in out if r["kind"] not in ("onboarding", "weekly")], key=lambda r: r["at"], reverse=True)
    for r in rest:
        r.pop("at", None)
    return head[:1] + rest + head[1:] if head and head[0]["kind"] == "onboarding" else rest + head


def can_send(client):
    weekly_on = (own_weekly(client) or master_weekly())
    weekly_on = bool(weekly_on and weekly_on.sending)
    last = {}
    for r in FormRequest.objects.filter(client=client).select_related("form").order_by("created_at"):
        last[r.form.master_id or r.form_id] = r
    sched = {s.form.master_id or s.form_id for s in
             FormSchedule.objects.filter(client=client, active=True).select_related("form")}
    out = []
    for f in Form.objects.filter(status="published").exclude(type="daily").prefetch_related("questions"):
        n = len(live_questions(f))
        if not n:
            continue
        has = ""
        if f.type == "weekly" and weekly_on:
            has = "Sending"
        elif f.id in sched:
            has = "Scheduled"
        elif f.id in last:
            has = f"Sent {_d(last[f.id].created_at)}"
        out.append({"id": str(f.id), "name": f.name, "type": f.type, "questions": n, "sub": FORM_SUB.get(f.type, ""),
                    "has": has})
    return out


# ------------------------------------------------------------------ one form


def _resolve(client, key):
    """(kind, object, form in use) for a list key."""
    if key == "weekly":
        own = own_weekly(client)
        return "weekly", own, own or master_weekly()
    kind, _, pk = key.partition(":")
    if kind == "req":
        r = get_object_or_404(FormRequest.objects.select_related("form"), id=pk, client=client)
        return "request", r, r.form
    if kind == "sub":
        s = get_object_or_404(Submission.objects.select_related("form"), id=pk, client=client)
        return "submission", s, s.form
    if kind == "sched":
        s = get_object_or_404(FormSchedule.objects.select_related("form"), id=pk, client=client)
        return "schedule", s, s.form
    raise serializers.ValidationError({"key": ["Unknown form."]})


def question_rows(form, first):
    per, _ = changes(form)
    return [{"id": q.id, "text": q.text, "type": q.type, "type_label": TYPE_LABEL.get(q.type, q.type),
             "required": q.required, "options": q.options, "changed": q.id in per,
             "change": (f"Added for {first}" if per.get(q.id) == "added" else per.get(q.id, ""))}
            for q in live_questions(form)]


def detail(client, key):
    first = _first(client)
    kind, obj, form = _resolve(client, key)
    master = master_of(form)
    _, summary = changes(form)
    out = {"key": key, "kind": kind, "name": form.name if form else "", "form_id": str(form.id) if form else None,
           "master_name": master.name if master else None,
           "edited": bool(form and form.status == Form.Status.CLIENT and summary not in ("", "no changes")),
           "changes": summary, "first": first}
    master_line = f'From master "{master.name}"' if master else "Only for " + first
    change_line = "no changes" if summary in ("", "no changes") else summary
    if kind in ("submission",) or (kind == "request" and obj.filled_at):
        sub = obj if kind == "submission" else Submission.objects.filter(request=obj).order_by("-created_at").first()
        st, label = _status(obj, form)
        when = sub.created_at if sub else obj.filled_at
        verb = "Signed" if st == "signed" else "Filled"
        out.update({"status": st, "status_label": label,
                    "cap": f"{verb} by {first} on {_d(when, '%-d %b %Y, %-I:%M %p').replace('AM', 'am').replace('PM', 'pm')}",
                    "sections": answers_of(sub) if sub else [], "submission_id": str(sub.id) if sub else None})
        return out
    out["questions"] = question_rows(form, first)
    if kind == "request":
        sent = _d(obj.created_at, "%a, %-d %b")
        out.update({"status": "waiting", "status_label": "Waiting",
                    "cap": f"{master_line} · {change_line} · sent {sent}, not answered yet",
                    "waiting": (f"{first} has not answered yet. A reminder went out on {_d(obj.reminded_at)}."
                                if obj.reminded_at else f"{first} has not answered yet. Sent {sent}."),
                    "actions": ["edit", "duplicate", "send_now", "reset", "stop", "remind"]})
        if form.status != Form.Status.CLIENT:
            out["actions"].remove("reset")
        return out
    if kind == "weekly":
        on = form.sending if form else False
        out.update({"status": "recurring" if on else "stopped", "status_label": "Recurring" if on else "Stopped",
                    "cap": f"{master_line} · {WEEKLY_DUE} · {change_line} · answers are in Logs"
                    if on else f"{master_line} · stopped · {change_line}",
                    "schedule": {"label": "Every Sunday", "time": "6:00 pm", "by": "Push"},
                    "actions": ["edit", "duplicate", "send_now", "reset", "stop" if on else "start"]})
        if obj is None:
            out["actions"].remove("reset")
        return out
    s = obj  # schedule
    out.update({"status": "recurring" if s.active and s.repeat != "once" else ("scheduled" if s.active else "stopped"),
                "status_label": ("Recurring" if s.repeat != "once" else "Scheduled") if s.active else "Stopped",
                "cap": f"{master_line} · {schedule_label(s).lower()}, {_clock(s.time)} · {change_line}",
                "schedule": {"label": schedule_label(s), "time": _clock(s.time), "by": _by_label(s.channels)},
                "actions": ["edit", "duplicate", "send_now", "reset", "stop" if s.active else "start"]})
    if form.status != Form.Status.CLIENT:
        out["actions"].remove("reset")
    return out


def editable_copy(client, key, actor):
    """Her copy of the form behind `key` (made on first save) and the master it follows."""
    kind, obj, form = _resolve(client, key)
    if kind in ("submission",) or (kind == "request" and obj.filled_at):
        raise serializers.ValidationError(f"{_first(client)} answered this one already. Send it again to change it.")
    if form is None:
        raise serializers.ValidationError("There is no weekly check-in in the library.")
    if form.status == Form.Status.CLIENT:
        return form, master_of(form)
    copy = _copy(form, client, actor)
    if kind == "request":
        obj.form = copy
        obj.save(update_fields=["form", "updated_at"])
    elif kind == "schedule":
        obj.form = copy
        obj.save(update_fields=["form", "updated_at"])
    return copy, form


# ------------------------------------------------------------------ views


def _when(data, client):
    """Send a form → When: once (now / a day) or a repeat."""
    mode = data.get("mode") or "once"
    channels, _ = BY.get(data.get("by") or "push", BY["push"])
    try:
        days = max(1, min(14, int(data.get("answer_days") or 2)))
    except (TypeError, ValueError):
        days = 2
    common = {"channels": channels, "answer_days": days, "auto_remind": bool(data.get("remind", True))}
    if mode == "once":
        day = data.get("send") or "now"
        if day == "now":
            return "now", common
        d = parse_date(str(day))
        if d is None or d < timezone.localdate():
            raise serializers.ValidationError({"send": ["Pick today or a later day."]})
        t = parse_time(str(data.get("time") or "10:00")) or time(10)
        when = _at(d, t)
        return "later", {**common, "repeat": "once", "next_at": when if when > timezone.now() else timezone.now()}
    if mode != "repeat":
        raise serializers.ValidationError({"mode": ["Use once or repeat."]})
    every = data.get("every") or "week"
    if every not in ("week", "month"):
        raise serializers.ValidationError({"every": ["Use week or month."]})
    t = parse_time(str(data.get("time") or "18:00"))
    if t is None:
        raise serializers.ValidationError({"time": ["Pick a time."]})
    until = parse_date(str(data.get("until") or "")) if data.get("until") else None
    try:
        weekday = int(data.get("weekday", 6)) % 7
        month_day = max(1, min(28, int(data.get("month_day", 1))))
    except (TypeError, ValueError):
        raise serializers.ValidationError({"weekday": ["Pick a day."]})
    return "repeat", {**common, "repeat": every, "weekday": weekday, "month_day": month_day, "time": t,
                      "until": until}


def _start(client, form, actor, data):
    """Send now, or make the schedule. Returns the list key of what was made."""
    how, opts = _when(data, client)
    if how == "now":
        r = send(client, form, actor, channels=opts["channels"], answer_days=opts["answer_days"],
                 auto_remind=opts["auto_remind"])
        return f"req:{r.id}"
    if form.type == "weekly" and how == "repeat":  # her weekly check-in (due every Sunday): switch it on
        if form.status == Form.Status.CLIENT:  # a new copy for her becomes her weekly check-in
            Form.objects.filter(type="weekly", status=Form.Status.CLIENT, client=client).exclude(id=form.id) \
                .update(deleted_at=timezone.now())
            if not form.sending:
                form.sending = True
                form.save(update_fields=["sending", "updated_at"])
        else:
            own = own_weekly(client)
            if own is not None and not own.sending:
                own.sending = True
                own.save(update_fields=["sending", "updated_at"])
        return "weekly"
    s = FormSchedule(client=client, form=form, created_by=actor, **opts)
    if s.repeat != "once":
        s.next_at = next_run(s)
    s.save()
    return f"sched:{s.id}"


def _stop_old(client, key):
    """"Instead of": the form this new copy replaces stops."""
    if not key:
        return
    kind, obj, form = _resolve(client, key)
    if kind == "weekly" and form is not None:
        if obj is None:
            obj = _copy(form, client, None)
            _copy_questions(form, obj)
        obj.sending = False
        obj.save(update_fields=["sending", "updated_at"])
    elif kind == "request" and not obj.filled_at:
        obj.delete()
    elif kind == "schedule":
        obj.active = False
        obj.save(update_fields=["active", "updated_at"])


class ClientFormsView(APIView):
    """GET: the tab's list (`sent`) and the library forms to send (`can_send`).
    POST: Send a form {form, mode: once|repeat, send: now|YYYY-MM-DD, answer_days, every: week|month, weekday,
    month_day, time, until, by: push|push_whatsapp|push_email, remind}."""

    permission_classes = [IsStaff]

    def get(self, request, client_pk):
        client = _client(request.user, client_pk)
        return Response({"sent": rows(client, request), "can_send": can_send(client), "first": _first(client)})

    def post(self, request, client_pk):
        client = _client(request.user, client_pk)
        form = get_object_or_404(Form, id=request.data.get("form"), status="published")
        with transaction.atomic():
            key = _start(client, form, request.user, request.data)
        return Response({"key": key, "row": next((r for r in rows(client) if r["key"] == key), None)}, status=201)


class ClientFormView(APIView):
    """One form of the list: GET the card; POST an action: remind · send_now · stop · start · reset."""

    permission_classes = [IsStaff]

    def get(self, request, client_pk, key):
        return Response(detail(_client(request.user, client_pk), key))

    def post(self, request, client_pk, key, act=None):
        client = _client(request.user, client_pk)
        first = _first(client)
        with transaction.atomic():
            kind, obj, form = _resolve(client, key)
            if act == "remind":
                if kind != "request" or obj.filled_at:
                    raise serializers.ValidationError(f"{first} answered this one already.")
                remind(obj)
                msg = f"Reminder sent to {first}"
            elif act == "send_now":
                if form is None:
                    raise serializers.ValidationError("There is no form to send.")
                r = send(client, form, request.user,
                         channels=(obj.channels if kind == "schedule" and obj.channels else None))
                return Response({"key": f"req:{r.id}", "message": f"{form.name} sent to {first}"})
            elif act == "stop":
                if kind == "weekly":
                    if form is None:
                        raise serializers.ValidationError("There is no weekly check-in to stop.")
                    if obj is None:
                        obj = _copy(form, client, request.user)
                        _copy_questions(form, obj)
                    obj.sending = False
                    obj.save(update_fields=["sending", "updated_at"])
                elif kind == "schedule":
                    obj.active = False
                    obj.save(update_fields=["active", "updated_at"])
                elif kind == "request" and not obj.filled_at:
                    obj.delete()
                    return Response({"key": None, "message": f"{form.name} withdrawn"})
                else:
                    raise serializers.ValidationError("This form is not being sent.")
                msg = f"{form.name} stopped for {first}"
            elif act == "start":
                if kind == "weekly" and obj is not None:
                    obj.sending = True
                    obj.save(update_fields=["sending", "updated_at"])
                elif kind == "schedule":
                    obj.active = True
                    if obj.repeat != "once":
                        obj.next_at = next_run(obj)
                        obj.active = obj.next_at is not None
                    obj.save(update_fields=["active", "next_at", "updated_at"])
                msg = f"{form.name} is on again for {first}"
            elif act == "reset":
                master = master_of(form)
                if form is None or form.status != Form.Status.CLIENT:
                    raise serializers.ValidationError("This form is the same as the master.")
                if master is None:
                    raise serializers.ValidationError("This form has no master to go back to.")
                # what still waits for an answer goes back to the master; answers already sent stay readable
                FormRequest.objects.filter(form=form, filled_at__isnull=True).update(form=master)
                FormSchedule.objects.filter(form=form).update(form=master)
                if kind == "weekly":
                    master_on = form.sending
                    form.soft_delete()
                    if not master_on:  # stopped stays stopped: a plain copy of the master, switched off
                        off = _copy(master, client, request.user)
                        _copy_questions(master, off)
                        off.sending = False
                        off.save(update_fields=["sending", "updated_at"])
                else:
                    form.soft_delete()
                msg = f"{master.name} reset to master"
            else:
                raise serializers.ValidationError({"action": ["Unknown action."]})
        activity_log(f"{act.replace('_', ' ')}: {form.name if form else ''}", "checkin", actor=request.user,
                     target=client, target_label=form.name if form else "", client=client)
        return Response({"key": key, "message": msg})


class ClientFormQuestionsView(APIView):
    """The per-client editor ("Edit Weekly check-in for Riya"): GET the questions of her copy (or of the master
    when there is no copy yet), PUT the whole list — the first save makes her copy."""

    permission_classes = [IsStaff]

    def get(self, request, client_pk, key):
        client = _client(request.user, client_pk)
        kind, obj, form = _resolve(client, key)
        first = _first(client)
        master = master_of(form)
        _, summary = changes(form)
        sched = {"label": "Every Sunday", "time": "6:00 pm", "by": "Push"} if kind == "weekly" else (
            {"label": schedule_label(obj), "time": _clock(obj.time), "by": _by_label(obj.channels)}
            if kind == "schedule" else {"label": "Once", "time": _d(obj.created_at, "%a, %-d %b") if obj else "",
                                        "by": "Push"})
        return Response({
            "key": key, "name": form.name if form else "", "master_name": master.name if master else None,
            "changes": summary or "no changes", "schedule": sched,
            "questions": question_rows(form, first),
            "types": [{"value": v, "label": TYPE_LABEL[v]} for v in
                      (QuestionType.SHORT, QuestionType.LONG, QuestionType.NUMBER, QuestionType.SCALE,
                       QuestionType.YES_NO, QuestionType.PHOTO)],
        })

    def put(self, request, client_pk, key):
        client = _client(request.user, client_pk)
        with transaction.atomic():
            copy, master = editable_copy(client, key, request.user)
            save_questions(copy, request.data.get("questions") or [], master)
        activity_log(f"edited {copy.name} for {client.full_name}", "checkin", actor=request.user, target=client,
                     target_label=copy.name, client=client)
        return Response(detail(client, key))


class ClientFormDuplicateView(APIView):
    """Duplicate and edit → Send copy: a new form only for her {source: list key | form: library id, name,
    questions, first_send: YYYY-MM-DD, instead_of: list key | "", and the Send a form `when` fields}."""

    permission_classes = [IsStaff]

    def post(self, request, client_pk):
        client = _client(request.user, client_pk)
        d = request.data
        if d.get("source"):
            _, _, src = _resolve(client, d["source"])
        else:
            src = get_object_or_404(Form, id=d.get("form"), status="published")
        if src is None:
            raise serializers.ValidationError("There is no form to copy.")
        master = master_of(src) or src
        name = " ".join(str(d.get("name") or "").split())[:120]
        if len(name) < 2:
            raise serializers.ValidationError({"name": ["Enter a form name."]})
        # ids from her current copy point back to the master question they came from
        alias = {q.id: q.copied_from_id for q in src.questions.all()} if src.status == Form.Status.CLIENT else {}
        items = []
        for q in d.get("questions") or []:
            if not isinstance(q, dict):
                continue
            qid = alias.get(q.get("id"), q.get("id")) if src.status == Form.Status.CLIENT else q.get("id")
            items.append({k: v for k, v in q.items() if k != "id"} | ({"id": qid} if qid else {}))
        with transaction.atomic():
            if master.type != "weekly":  # a new weekly copy replaces her weekly check-in by itself
                _stop_old(client, d.get("instead_of") or "")
            copy = _copy(master, client, request.user, name=name)
            save_questions(copy, items, master)
            when = dict(d)
            if copy.type == "weekly":
                when.update({"mode": "repeat", "every": "week"})
            elif d.get("first_send") and d.get("mode", "once") == "once":
                when["send"] = "now" if str(d["first_send"]) <= str(timezone.localdate()) else d["first_send"]
            key = _start(client, copy, request.user, when)
        activity_log(f"sent a new form to {client.full_name}", "checkin", actor=request.user, target=client,
                     target_label=copy.name, client=client)
        return Response({"key": key}, status=201)
