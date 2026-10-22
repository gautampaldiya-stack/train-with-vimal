"""Admin → Forms & check-ins and the Form builder (boards `Forms` / `FormBuilder`, D-50).

- Builder changes to a published form are kept as a draft (`Form.draft_questions`) until Publish: clients keep
  getting the live questions ("Clients get the old version until you publish"). A form that was never published
  saves straight into its questions.
- "How it is sent": the automations that send the form, else the built-in way the app asks it (the onboarding
  questionnaire at sign-up, the live weekly and daily check-ins), else "Sent by hand".
- "Answers so far": this month's sends and answers, over the clients the person can see."""

from datetime import timedelta

from django.db import transaction
from django.utils import timezone

from apps.clients.services import visible_clients

from .models import Answer, Form, FormRequest, Question, Submission

# Fields a question dict carries (QuestionSerializer); `id` and `profile_key` are handled apart.
Q_FIELDS = ("text", "type", "options", "scale_labels", "allow_other", "help_text", "required", "metric")


def live_ids():
    """{"onboarding" | "weekly" | "daily": id of the form the client app uses now}."""
    from apps.clients.onboarding import questionnaire

    out = {}
    for t in ("weekly", "daily"):
        f = Form.objects.filter(type=t, status="published").only("id").first()
        if f:
            out[t] = f.id
    q = questionnaire()
    if q:
        out["onboarding"] = q.id
    return out


BUILT_IN = {
    "onboarding": "Client setup · asked at sign-up",
    "weekly": "Client app · every week, due Sunday 6 pm",
    "daily": "Client app · every day",
}


def built_in(form, live):
    """The built-in line of "How it is sent", or ""."""
    return next((BUILT_IN[k] for k, fid in live.items() if fid == form.id), "")


# ---------------------------------------------------------------- questions and drafts


def question_dict(q):
    return {"id": q.id, **{k: getattr(q, k) for k in Q_FIELDS}, "profile_key": q.profile_key}


def live_questions(form):
    return [question_dict(q) for q in form.questions.all() if not q.is_removed]


def shown_questions(form):
    """What the builder shows: the draft when there is one, else the live questions."""
    return form.draft_questions if form.draft_questions is not None else live_questions(form)


def _keep_keyed(form, items):
    """A question that fills a profile field (`profile_key`) keeps its answer type and options; only its words, help
    and Required change. New questions never get a key."""
    keyed = {q.id: q for q in form.questions.all() if q.profile_key}
    out = []
    for d in items:
        d = {k: v for k, v in d.items() if k in Q_FIELDS or k == "id"}
        q = keyed.get(d.get("id"))
        if q:
            d.update(type=q.type, options=q.options, scale_labels=q.scale_labels, allow_other=q.allow_other,
                     metric=q.metric, profile_key=q.profile_key)
        else:
            d["profile_key"] = ""
        out.append(d)
    return out


def write_questions(form, items):
    """Save the whole list into the form's questions (ids keep old answers linked). Removed questions that have
    answers stay, hidden (`is_removed`), so the answers stay readable."""
    with transaction.atomic():
        keep = []
        mine = {q.id: q for q in form.questions.all()}
        for i, d in enumerate(items):
            q = mine.get(d.get("id")) or Question(form=form)
            for k in Q_FIELDS:
                if k in d:
                    setattr(q, k, d[k])
            if q.pk is None:
                q.profile_key = ""
            q.order, q.is_removed = i, False
            q.save()
            keep.append(q.id)
        gone = form.questions.exclude(id__in=keep)
        answered = set(Answer.objects.filter(question__in=gone).values_list("question_id", flat=True))
        gone.exclude(id__in=answered).delete()
        Question.objects.filter(id__in=answered).update(is_removed=True, order=999)


def save_builder(form, items):
    """The builder's autosave: a published form keeps the change as a draft; a draft form saves it."""
    items = _keep_keyed(form, items)
    if form.status == Form.Status.PUBLISHED:
        form.draft_questions = items
        form.save(update_fields=["draft_questions", "updated_at"])
    else:
        write_questions(form, items)
        form.save(update_fields=["updated_at"])


def publish(form):
    with transaction.atomic():
        if form.draft_questions is not None:
            write_questions(form, form.draft_questions)
        form.draft_questions = None
        form.status = Form.Status.PUBLISHED
        form.save(update_fields=["draft_questions", "status", "updated_at"])


def to_draft(form):
    """ "Move back to draft" on a published form: start a draft of the live questions. The form stays live."""
    if form.draft_questions is None:
        form.draft_questions = live_questions(form)
        form.save(update_fields=["draft_questions", "updated_at"])


def discard_draft(form):
    form.draft_questions = None
    form.save(update_fields=["draft_questions", "updated_at"])


# ---------------------------------------------------------------- Answers so far


def _sundays(start, today):
    first = start + timedelta(days=(6 - start.weekday()) % 7)
    return 0 if first > today else (today - first).days // 7 + 1


def form_stats(form, user, live=None):
    """{sent, answered, rate, latest: {id, first_name} | None} for this month."""
    live = live if live is not None else live_ids()
    now = timezone.localtime()
    today = now.date()
    start = today.replace(day=1)
    start_dt = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    clients = visible_clients(user)
    latest = None
    if form.id in (live.get("weekly"), live.get("daily")):
        active = clients.filter(status="active", is_active=True).count()
        due = _sundays(start, today) if form.type == "weekly" else today.day
        subs = Submission.objects.filter(client__in=clients, form_type=form.type, date__gte=start)
        sent, answered = active * due, subs.count()
        last = subs.select_related("client").order_by("-created_at").first()
        latest = last.client if last else None
    elif form.id == live.get("onboarding"):
        joined = clients.filter(date_joined__gte=start_dt)
        sent = joined.count()
        answered = joined.filter(client_profile__onboarding__has_key="agree").count()
        latest = clients.filter(client_profile__onboarding__has_key="agree").order_by("-date_joined").first()
    else:
        reqs = FormRequest.objects.filter(form=form, client__in=clients, created_at__gte=start_dt)
        sent, answered = reqs.count(), reqs.filter(filled_at__isnull=False).count()
        last = (Submission.objects.filter(form=form, client__in=clients).select_related("client")
                .order_by("-created_at").first())
        latest = last.client if last else None
    answered = min(answered, sent) if sent else answered
    return {
        "sent": sent,
        "answered": answered,
        "rate": round(answered * 100 / sent) if sent else None,
        "latest": {"id": str(latest.id), "first_name": latest.full_name.split(" ")[0]} if latest else None,
    }
