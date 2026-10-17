"""Client profile (staff) → Logs → Daily / Weekly check-ins tables, and the Progress tab's extra numbers.

Every day (or Sunday) of the range is a row, so a check-in that never came shows as "Not sent" / "Missed".
"""
from datetime import timedelta

from django.utils import timezone

from .defaults import SCALE_ENERGY, SCALE_HUNGER
from .client_page import answer_photos
from .models import DEFAULT_MEASURES, MEASURES, PhotoSet, Submission


def _label(v, labels):
    try:
        i = int(round(float(v)))
    except (TypeError, ValueError):
        return None
    return labels[i - 1] if 1 <= i <= len(labels) else None


def _long_answer(sub):
    for a in sub.answers.all():
        if a.question.type == "long" and isinstance(a.value, str) and a.value.strip():
            return a.value.strip()
    return (sub.metrics or {}).get("note") or ""


def daily_rows(client, start, end, params, request=None):
    from apps.clients.logs import days_desc, page_of
    from apps.habits.models import HabitLog
    from apps.nutrition.models import WaterLog

    today = timezone.localdate()
    subs = {}
    for s in (Submission.objects.filter(client=client, form_type="daily", date__range=(start, end))
              .prefetch_related("answers__question").order_by("created_at")):
        subs[s.date] = s  # the last one sent that day
    steps = dict(HabitLog.objects.filter(client=client, date__range=(start, end), habit__name__icontains="steps",
                                         value__gt=0).values_list("date", "value"))
    water = dict(WaterLog.objects.filter(client=client, date__range=(start, end), ml__gt=0).values_list("date", "ml"))
    rows = []
    for d in days_desc(start, end, client):
        s = subs.get(d)
        if s is None and d == today:
            continue  # today's may still come
        m = (s.metrics or {}) if s else {}
        sleep = m.get("sleep_hours")
        rows.append({
            "id": str(s.id) if s else None, "date": d, "sent_at": s.created_at if s else None,
            "sleep": float(sleep) if isinstance(sleep, (int, float)) else None,
            "energy": _label(m.get("energy"), SCALE_ENERGY), "mood": _label(m.get("mood"), SCALE_ENERGY),
            "hunger": _label(m.get("hunger"), SCALE_HUNGER), "soreness": m.get("soreness"),
            "steps": steps.get(d), "water": round(water[d] / 1000, 1) if d in water else None,
            "weight": float(m["weight"]) if isinstance(m.get("weight"), (int, float)) else None,
            "note": _long_answer(s) if s else "",
            "reviewed": bool(s and s.reviewed_at), "reply": s.reply if s else "",
        })
    week = [today - timedelta(days=i) for i in range(7)]
    sent = Submission.objects.filter(client=client, form_type="daily", date__in=week).values("date").distinct().count()
    out = page_of(rows, params)
    out["week"] = {"sent": sent, "days": 7}
    return out


def weekly_rows(client, start, end, params, request=None):
    from apps.clients.logs import client_start, page_of

    from .services import week_number

    today = timezone.localdate()
    begin = max(start, client_start(client))
    subs = list(Submission.objects.filter(client=client, form_type="weekly", date__range=(begin, end + timedelta(days=1)))
                .select_related("reviewed_by").prefetch_related("answers__question").order_by("-created_at"))

    def sunday(d):
        return d + timedelta(days=(6 - d.weekday()) % 7)

    sets = {p.submission_id: p for p in PhotoSet.objects.filter(client=client, submission__in=subs)
            .prefetch_related("photos")}
    by_week = {}
    for s in subs:
        by_week.setdefault(sunday(s.date if s.date.weekday() != 0 else s.date - timedelta(days=1)), s)
    rows = []
    d = sunday(min(end, today))
    first = sunday(begin)
    while d >= first:
        s = by_week.get(d)
        if s is not None:
            m = s.metrics or {}
            photos = answer_photos(s, request)
            if not photos:  # photos sent from the Progress page with this check-in
                ps = sets.get(s.id)
                photos = [{"label": p.get_pose_display(), "pose": p.pose,
                           "image": request.build_absolute_uri(p.image.url) if request else p.image.url}
                          for p in (ps.photos.all() if ps else []) if not p.private]
            rows.append({
                "id": str(s.id), "week": s.week_number or week_number(client, s.date), "date": s.date,
                "sent_at": s.created_at, "status": "reviewed" if s.reviewed_at else "to_review",
                "weight": float(m["weight"]) if isinstance(m.get("weight"), (int, float)) else None,
                "photo_count": len(photos), "photos": photos, "note": _long_answer(s), "reply": s.reply,
                "reviewer": s.reviewed_by.full_name if s.reviewed_by else None,
            })
        elif d < today and d >= client_start(client) + timedelta(days=6):
            rows.append({"id": None, "week": week_number(client, d), "date": d, "status": "missed"})
        d -= timedelta(days=7)
    return page_of(rows, params)


def personal_bests(client, limit=8):
    """Personal bests table: per exercise the heaviest set of the first day logged (Start) and the heaviest
    set ever (Best), most-logged exercises first."""
    from django.db.models import Count

    from apps.training.models import SetLog

    base = SetLog.objects.filter(workout__client=client, workout__status="completed", done=True, is_warmup=False,
                                 weight_kg__isnull=False, weight_kg__gt=0)
    out = []
    for row in base.values("exercise_id", "exercise__name").annotate(n=Count("id")).order_by("-n")[:limit]:
        sets = list(base.filter(exercise_id=row["exercise_id"]).order_by("workout__date", "-weight_kg", "-reps")
                    .values("workout__date", "weight_kg", "reps"))
        first = sets[0]
        best = max(sets, key=lambda s: (s["weight_kg"], s["reps"] or 0))
        out.append({"exercise": row["exercise_id"], "name": row["exercise__name"],
                    "start": {"kg": float(first["weight_kg"]), "reps": first["reps"], "date": first["workout__date"]},
                    "best": {"kg": float(best["weight_kg"]), "reps": best["reps"], "date": best["workout__date"]}})
    return out


def progress_extras(client):
    cp = client.client_profile
    tracked = set(cp.measure_keys or DEFAULT_MEASURES)
    return {
        "goal": float(cp.target_weight_kg) if cp.target_weight_kg is not None else None,
        "start": {"kg": float(cp.start_weight_kg) if cp.start_weight_kg is not None else None,
                  "date": cp.start_date or client.date_joined.date()},
        "measures": [{"key": k, "label": lbl, "unit": u, "tracked": k in tracked} for k, lbl, u in MEASURES],
        "measure_every_weeks": cp.photo_every_weeks,
        "lifts": personal_bests(client),
    }
