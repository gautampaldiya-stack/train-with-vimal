"""Client profile → History tab (boards TrainerClientProfile / …Mobile, History).

Everything that mattered in one client's time with the gym, built from what is already stored: plan assignments
(workout, meal, supplements, habits), trainer changes and goal edits (ActivityEvent), weigh-ins, check-ins and
forms, flagged notes. Milestones ("Lost 5 kg since joining", best streak, finished a program) are computed.
"""
from collections import defaultdict
from datetime import date, timedelta

from django.utils import timezone

from apps.common.utils import dfmt

from . import metrics

# Journey item kind → filter chip (board: All · Plans and trainer · Milestones and goals · Check-ins and forms ·
# Health · Account).
GROUPS = {"plan": "plans", "trainer": "plans", "mile": "miles", "goal": "miles", "check": "checks",
          "form": "checks", "health": "health", "acct": "acct"}
TYPE_LABELS = {"plan": "Plan", "trainer": "Trainer", "mile": "Milestone", "goal": "Goal", "check": "Check-in",
               "form": "Form", "health": "Health", "acct": "Account"}
DIETS = {"veg": "Vegetarian", "egg": "Eggetarian", "non_veg": "Non-veg", "vegan": "Vegan", "jain": "Jain"}


def _f(v):
    return float(v) if v is not None else None


def _kg(v):
    return f"{float(v):.1f} kg"


def _kg0(v):
    s = f"{float(v):.1f}"
    return f"{s[:-2] if s.endswith('.0') else s} kg"


def _d(v):
    return dfmt(v, "%a, %-d %b")


def _dy(v):
    return dfmt(v, "%a, %-d %b %Y")


def _dm(v):
    return dfmt(v, "%-d %b")


def _local(dt):
    return timezone.localtime(dt).date() if dt else None


def _pron(user):
    return {"female": "her", "male": "his"}.get(user.gender, "their")


def _span(a, b):
    """'8 months', '3 weeks', '5 days' between two dates."""
    days = max(0, (b - a).days)
    months = (b.year - a.year) * 12 + b.month - a.month - (1 if b.day < a.day else 0)
    if months >= 1:
        return f"{months} month{'s' if months != 1 else ''}"
    if days >= 7:
        return f"{days // 7} week{'s' if days >= 14 else ''}"
    return f"{days} day{'s' if days != 1 else ''}"


# ─────────────────────────────── goal edits (written by ClientViewSet.partial_update)


def goal_snapshot(user):
    cp = user.client_profile
    return {"goal": cp.goal, "target": _f(cp.target_weight_kg), "health": cp.health_notes or ""}


def log_goal_changes(user, before, actor):
    """Goal, goal weight and health notes keep their history in the timeline, so History can say
    "68 kg · was 70 kg until Jul" and list "Goal weight changed"."""
    from apps.activity.services import log

    cp = user.client_profile
    cp.refresh_from_db()
    after = goal_snapshot(user)
    if before["target"] != after["target"]:
        log("changed goal weight", "client", actor=actor, target=user, target_label=user.full_name, client=user,
            change=(_kg0(before["target"]) if before["target"] else "Not set",
                    _kg0(after["target"]) if after["target"] else "Not set"), meta={"history": "goal_weight"})
    if before["goal"] != after["goal"]:
        from .models import Goal

        lbl = dict(Goal.choices)
        log("changed goal", "client", actor=actor, target=user, target_label=user.full_name, client=user,
            change=(lbl.get(before["goal"], "Not set"), lbl.get(after["goal"], "Not set")), meta={"history": "goal"})
    if before["health"].strip() != after["health"].strip():
        log("updated health notes", "client", actor=actor, target=user, target_label=user.full_name, client=user,
            meta={"history": "health", "note": after["health"].strip().split("\n")[0][:200]})


# ─────────────────────────────── building blocks


class _Ctx:
    def __init__(self, user):
        from apps.activity.models import ActivityEvent
        from apps.checkins.models import Submission, WeightLog
        from apps.habits.models import HabitAssignment, SupplementAssignment
        from apps.nutrition.models import MealPlanAssignment
        from apps.training.models import ProgramAssignment

        self.user = user
        self.cp = user.client_profile
        self.today = timezone.localdate()
        self.joined = min(filter(None, [self.cp.start_date, _local(user.date_joined)]))
        self.programs = list(ProgramAssignment.objects.filter(client=user)
                             .select_related("program", "custom_program", "assigned_by").order_by("start_date",
                                                                                                    "created_at"))
        self.meals = list(MealPlanAssignment.objects.filter(client=user).select_related("plan", "assigned_by")
                          .order_by("start_date", "created_at"))
        self.supps = list(SupplementAssignment.objects.filter(client=user).select_related("plan", "assigned_by")
                          .prefetch_related("plan__items").order_by("start_date"))
        self.habits = list(HabitAssignment.objects.filter(client=user).select_related("habit", "assigned_by")
                           .order_by("start_date"))
        self.weights = list(WeightLog.objects.filter(client=user).order_by("date").values_list("date", "weight_kg"))
        self.subs = list(Submission.objects.filter(client=user).select_related("form", "reviewed_by")
                         .order_by("date", "created_at"))
        self.events = list(ActivityEvent.objects.filter(client=user).order_by("created_at"))
        self.start_w = _f(self.cp.start_weight_kg) or (_f(self.weights[0][1]) if self.weights else None)
        self.current_w = _f(self.weights[-1][1]) if self.weights else _f(self.cp.current_weight_kg)
        self.target_w = _f(self.cp.target_weight_kg)
        self.planned = self._planned_days()
        self.done_days = self._done_days()

    def _planned_days(self):
        out = set()
        for pa in self.programs:
            if pa.status == "up_next":
                continue
            end = min(pa.end_date or self.today, self.today)
            out.update(metrics.planned_workout_days(pa, pa.start_date, end))
        return out

    def _done_days(self):
        from apps.training.models import WorkoutLog

        return list(WorkoutLog.objects.filter(client=self.user, status="completed").order_by("date")
                    .values_list("date", flat=True))

    def weekly(self):
        return [s for s in self.subs if s.form_type == "weekly"]

    def expected_weeks(self):
        """Sundays a weekly check-in was due: from the first full week after joining up to the last Sunday."""
        first = self.joined + timedelta(days=(6 - self.joined.weekday()) % 7)
        if first == self.joined:
            first += timedelta(days=7)
        last = self.today - timedelta(days=(self.today.weekday() + 1) % 7)
        out, d = [], first
        while d <= last:
            out.append(d)
            d += timedelta(days=7)
        return out

    def missed_weeks(self):
        sent = {s.date - timedelta(days=s.date.weekday()) for s in self.weekly()}
        return [(i + 1, d) for i, d in enumerate(self.expected_weeks())
                if (d - timedelta(days=6)) not in sent]

    def best_streak(self):
        """Longest run of days with something logged (a workout, a meal or a daily check-in): (days, last day)."""
        from apps.nutrition.models import MealDayState

        days = set(self.done_days) | {s.date for s in self.subs if s.form_type == "daily"}
        days |= set(MealDayState.objects.filter(client=self.user, status="logged").values_list("date", flat=True))
        best, end, run, prev = 0, None, 0, None
        for d in sorted(days):
            run = run + 1 if prev and (d - prev).days == 1 else 1
            if run > best:
                best, end = run, d
            prev = d
        return best, end


def _who(user, ctx):
    if user is None:
        return "Auto"
    return user.full_name


def _item(kind, title, detail, day, who, badge="", tone=""):
    return {"kind": kind, "group": GROUPS[kind], "title": title, "detail": detail, "date": day, "who": who,
            "badge": badge, "tone": tone}


# ─────────────────────────────── journey


def _plan_items(ctx):
    items = []
    pron = _pron(ctx.user)
    prev = None
    for pa in ctx.programs:
        p = pa.effective_program
        who = _who(pa.assigned_by, ctx)
        if pa.status == "up_next":
            cur = next((x for x in ctx.programs if x.status == "active"), None)
            items.append(_item("plan", f"{p.name} set as Up next",
                               f"Starts {_d(pa.start_date)}" + (f" after {cur.effective_program.name} ends" if cur else "")
                               + f". {p.weeks} weeks, {p.days_per_week} days a week.",
                               _local(pa.created_at), who, "Up next", "info"))
            continue
        bits = []
        if prev is not None and prev.end_date and (pa.start_date - prev.end_date).days <= 7:
            bits.append(f"Replaced {prev.effective_program.name}.")
        else:
            bits.append(f"{p.weeks} weeks, {p.days_per_week} days a week.")
        if pa.custom_program_id:
            bits.append(f"{pron.capitalize()} copy is edited for {pron if pron != 'their' else 'them'}.")
        items.append(_item("plan", f"Started {p.name}", " ".join(bits), pa.start_date, who, "Workout", "neutral"))
        if pa.status == "ended" and pa.end_date:
            full = (pa.end_date - pa.start_date).days + 1 >= p.weeks * 7 - 3
            planned = [d for d in ctx.planned if pa.start_date <= d <= pa.end_date]
            done = len({d for d in ctx.done_days if pa.start_date <= d <= pa.end_date})
            pct = f" · {round(100 * min(done, len(planned)) / len(planned))}% of workouts done" if planned else ""
            if full:
                items.append(_item("plan", f"Finished {p.name}", f"{p.weeks} weeks{pct}.", pa.end_date, "Auto",
                                   "Completed", "ok"))
            else:
                weeks = max(1, ((pa.end_date - pa.start_date).days + 1) // 7)
                items.append(_item("plan", f"Ended {p.name}", f"After {weeks} of {p.weeks} weeks{pct}.",
                                   pa.end_date, "Auto", "Workout", "neutral"))
        prev = pa

    prev = None
    for ma in ctx.meals:
        m = ma.plan
        line = f"{m.kcal_target:,} kcal"
        if prev is not None:
            pk = prev.plan.kcal_target
            line = (f"Down from {pk:,} kcal." if m.kcal_target < pk else f"Up from {pk:,} kcal."
                    if m.kcal_target > pk else f"Same {pk:,} kcal.") + f" Protein target {m.protein_g} g."
            title = f"Moved to {m.name}"
        else:
            line = f"{line} · {m.get_diet_display().lower()}. Protein target {m.protein_g} g."
            title = f"Started meal plan {m.name}"
        if ma.status == "up_next":
            title, line = f"{m.name} set as Up next", f"Starts {_d(ma.start_date)}."
        items.append(_item("plan", title, line, ma.start_date if ma.status != "up_next" else _local(ma.created_at),
                           _who(ma.assigned_by, ctx), "Up next" if ma.status == "up_next" else "Meal plan",
                           "info" if ma.status == "up_next" else "neutral"))
        if ma.status != "up_next":
            prev = ma

    for sa in ctx.supps:
        names = [i.name for i in sa.plan.items.all()]
        items.append(_item("plan", f"{sa.plan.name} supplements added", ", ".join(names[:5]) + "." if names else "",
                           sa.start_date, _who(sa.assigned_by, ctx), "Supplements", "neutral"))
        if not sa.active:
            items.append(_item("plan", f"{sa.plan.name} supplements stopped", "", _local(sa.updated_at), "Auto",
                               "Supplements", "neutral"))

    by_day = defaultdict(list)
    for ha in ctx.habits:
        by_day[ha.start_date].append(ha)
    for day, rows in sorted(by_day.items()):
        names = [h.habit.name for h in rows]
        title = f"{names[0]} habit added" if len(names) == 1 else f"{len(names)} habits added"
        detail = ", ".join(names) + "." if len(names) > 1 else ""
        on = day
        if day > ctx.today:  # added now, starts later
            on = min(_local(h.created_at) for h in rows)
            detail = f"{detail} Starts {_d(day)}.".strip()
        by = next((h.assigned_by for h in rows if h.assigned_by), None)
        items.append(_item("plan", title, detail, on, _who(by, ctx), "Habits", "neutral"))
    return items


def _trainer_items(ctx):
    changes = [e for e in ctx.events if e.verb == "changed trainer"]
    items = []
    first = changes[0].change_from if changes and changes[0].change_from != "No trainer" else None
    if not changes and ctx.cp.trainer:
        first = ctx.cp.trainer.full_name
    if first:
        start = next((e for e in ctx.events if e.verb in ("added a client", "approved a sign-up")), None)
        items.append(_item("trainer", f"{first} assigned as trainer", "", ctx.joined,
                           start.actor_label if start else "Auto", "Trainer", "neutral"))
    for e in changes:
        detail = f"Took over from {e.change_from}." if e.change_from and e.change_from != "No trainer" else ""
        items.append(_item("trainer", f"{e.change_to} assigned as trainer", detail, _local(e.created_at),
                           e.actor_label, "Trainer", "neutral"))
    return items


def _check_items(ctx):
    items = []
    for s in ctx.subs:
        if s.form_type == "daily":
            continue
        if s.form_type == "weekly":
            wk = f"Week {s.week_number} check-in" if s.week_number else "Weekly check-in"
            m = s.metrics or {}
            bits = [_kg(m["weight"])] if m.get("weight") is not None else []
            if s.reviewed_at:
                reviewer = s.reviewed_by.full_name if s.reviewed_by else "Coach"
                if s.reply:
                    bits.append(f"{reviewer.split(' ')[0]} replied: “{s.reply.strip()[:120]}”")
                items.append(_item("check", f"{wk} reviewed", ". ".join(bits), _local(s.reviewed_at), reviewer))
            else:
                items.append(_item("check", f"{wk} sent", ". ".join(bits + ["Waiting for review."]), s.date,
                                   ctx.user.full_name, "To review", "warn"))
        else:
            kind = "acct" if s.form_type == "onboarding" else "form"
            items.append(_item(kind, f"{s.form.name} answered" if kind == "form" else "Onboarding form filled",
                               "", s.date, ctx.user.full_name))
    for n, d in ctx.missed_weeks():
        items.append(_item("check", "Missed a check-in", f"Week {n}. Nothing was sent by {_d(d)}.", d, "Auto",
                           "Missed", "bad"))
    return items


def _milestones(ctx):
    items = []
    s = ctx.start_w
    if s is not None and ctx.weights:
        losing = ctx.target_w is None or ctx.target_w <= s
        reached = set()
        goal_hit = False
        for day, kg in ctx.weights:
            kg = float(kg)
            delta = (s - kg) if losing else (kg - s)
            for k in range(1, int(delta + 1e-9) + 1):
                if k not in reached:
                    reached.add(k)
                    items.append(_item("mile", f"{'Lost' if losing else 'Gained'} {k} kg since joining",
                                       f"{_kg(s)} to {_kg(kg)} in {_span(ctx.joined, day)}.", day, "Auto",
                                       "Milestone", "ok"))
            if ctx.target_w is not None and not goal_hit and ((losing and kg <= ctx.target_w) or
                                                               (not losing and kg >= ctx.target_w)):
                goal_hit = True
                items.append(_item("mile", "Reached goal weight", f"{_kg(kg)} · goal {_kg0(ctx.target_w)}.", day,
                                   "Auto", "Milestone", "ok"))
    best, end = ctx.best_streak()
    if best >= 7:
        items.append(_item("mile", f"{best} day streak", f"{_pron(ctx.user).capitalize()} best streak so far.", end,
                           "Auto", "Milestone", "ok"))
    for e in ctx.events:
        h = (e.meta or {}).get("history")
        if h == "goal_weight":
            items.append(_item("goal", "Goal weight changed", f"{e.change_from} became {e.change_to}.",
                               _local(e.created_at), e.actor_label, "Goal", "warn"))
        elif h == "goal":
            items.append(_item("goal", "Goal changed", f"{e.change_from} became {e.change_to}.",
                               _local(e.created_at), e.actor_label, "Goal", "warn"))
    return items


def _health_items(ctx):
    from .models import ClientNote

    items = []
    health = (ctx.cp.onboarding or {}).get("health") or {}
    hurt = [x.replace("_", " ") for x in (health.get("injuries") or []) + (health.get("conditions") or [])
            if x and x != "none"]
    if hurt:
        items.append(_item("health", "Health form: " + ", ".join(hurt), "From onboarding.", ctx.joined,
                           ctx.user.full_name, "Health", "warn"))
    for e in ctx.events:
        if (e.meta or {}).get("history") == "health":
            items.append(_item("health", "Health notes updated", (e.meta or {}).get("note", ""), _local(e.created_at),
                               e.actor_label, "Health", "warn"))
    for n in ClientNote.objects.filter(client=ctx.user, is_flag=True).select_related("author"):
        items.append(_item("health", n.body.strip().split("\n")[0][:90], n.body.strip()[90:200].strip(),
                           _local(n.created_at), n.author.full_name if n.author else "Coach", "Flagged", "warn"))
    return items


def _account_items(ctx):
    cp, u = ctx.cp, ctx.user
    added = next((e for e in ctx.events if e.verb == "added a client"), None)
    who = u.full_name
    if cp.signup_source == "added":
        who = cp.invited_by.full_name if cp.invited_by else (added.actor_label if added else "Auto")
    items = [_item("acct", "Joined Train With Vimal", _came_from(ctx, sentence=True), ctx.joined, who,
                   "Joined", "info")]
    if cp.onboarding and not any(s.form_type == "onboarding" for s in ctx.subs):
        items.append(_item("acct", "Onboarding form filled", _onboarding_line(ctx), ctx.joined, u.full_name))
    for e in ctx.events:
        if e.verb in ("paused a client", "resumed a client"):
            items.append(_item("acct", "Paused" if e.verb.startswith("paused") else "Resumed", "",
                               _local(e.created_at), e.actor_label))
    return items


def _came_from(ctx, sentence=False):
    cp = ctx.cp
    if cp.invite_link_id and cp.invite_link:
        lbl = cp.invite_link.label or "an invite link"
        return f"Signed up from {lbl}." if sentence else lbl
    if cp.signup_source == "added":
        added = next((e for e in ctx.events if e.verb == "added a client"), None)
        by = cp.invited_by.full_name if cp.invited_by else (added.actor_label if added else "the team")
        return f"Added by {by}." if sentence else f"Added by {by}"
    src = cp.get_signup_source_display()
    return f"Signed up on the {src}." if sentence else src


def _onboarding_line(ctx):
    on = ctx.cp.onboarding or {}
    goal = (on.get("goal") or {}).get("goal")
    about = on.get("about") or {}
    food = on.get("food") or {}
    days = len((on.get("schedule") or {}).get("days") or [])
    from .models import Goal

    bits = []
    if goal:
        bits.append(f"Goal: {dict(Goal.choices).get(goal, goal).lower()}.")
    body = [x for x in (_kg(about["weight_kg"]) if about.get("weight_kg") else "",
                        f"{about['height_cm']:g} cm" if isinstance(about.get("height_cm"), (int, float)) else "",
                        DIETS.get(food.get("diet"), "").lower(),
                        f"trains {days} days a week" if days else "") if x]
    if body:
        bits.append(", ".join(body) + ".")
    return " ".join(bits)


def journey(ctx):
    items = (_plan_items(ctx) + _trainer_items(ctx) + _check_items(ctx) + _milestones(ctx) + _health_items(ctx)
             + _account_items(ctx))
    # Same day, oldest first from the bottom: Joined, then the trainer, then onboarding, then the rest.
    order = {"acct": 2, "trainer": 1}
    items.sort(key=lambda i: (i["date"] or ctx.joined, 0 if i["badge"] == "Joined" else order.get(i["kind"], 5)),
               reverse=True)
    return items


def _month_summary(ctx, y, m):
    first = date(y, m, 1)
    last = (date(y + (m == 12), m % 12 + 1, 1) - timedelta(days=1))
    done = len({d for d in ctx.done_days if first <= d <= last})
    planned = len([d for d in ctx.planned if first <= d <= last])
    sent = len([s for s in ctx.weekly() if first <= s.date <= last])
    due = len([d for d in ctx.expected_weeks() if first <= d <= last])
    bits = []
    if first <= ctx.joined <= last:
        bits.append("Joined")
    if planned and planned != done:
        bits.append(f"{done} of {planned} workouts")
    elif done or planned:
        bits.append(f"{done} workout{'s' if done != 1 else ''}")
    if due and sent < due:
        bits.append(f"{sent} of {due} check-ins")
    elif sent:
        bits.append(f"{sent} check-in{'s' if sent != 1 else ''}")
    before = [float(kg) for d, kg in ctx.weights if d < first]
    inside = [float(kg) for d, kg in ctx.weights if first <= d <= last]
    if inside and (before or len(inside) > 1):
        delta = inside[-1] - (before[-1] if before else inside[0])
        if abs(delta) >= 0.05:
            now = first <= ctx.today <= last
            bits.append(f"{'−' if delta < 0 else '+'}{abs(delta):.1f} kg" + (" so far" if now else ""))
    return " · ".join(bits)


# ─────────────────────────────── summary, chart, side cards


def _summary(ctx):
    planned = len(ctx.planned)
    done_set = set(ctx.done_days)
    done = len(done_set)
    best, _ = ctx.best_streak()
    exp = len(ctx.expected_weeks())
    sent = len(ctx.weekly())
    missed = len(ctx.missed_weeks())
    s, c, t = ctx.start_w, ctx.current_w, ctx.target_w
    change = round(c - s, 1) if s is not None and c is not None else None
    to_goal = round(abs(c - t), 1) if c is not None and t is not None else None
    toward = None
    if change is not None and t is not None and s is not None:
        toward = (change < 0) == (t < s) if change else None
    return {
        "joined": ctx.joined,
        "duration": _span(ctx.joined, ctx.today),
        "start_weight": s, "current_weight": c, "target_weight": t, "weight_change": change, "to_goal": to_goal,
        "toward_goal": toward,
        "workouts_done": done, "workouts_planned": max(planned, done),
        "workouts_pct": round(100 * min(done, planned) / planned) if planned else None,
        "best_streak": best,
        "checkins_sent": sent, "checkins_expected": max(exp, sent), "checkins_missed": missed,
        "checkins_pct": round(100 * min(sent, exp) / exp) if exp else None,
    }


def _bar(label, start, end, status, tip):
    return {"label": label, "start": start, "end": end, "status": status, "tip": tip}


def _timeline(ctx):
    today = ctx.today
    rows = {"trainer": [], "workout": [], "meal": [], "supplements": [], "habits": []}
    # Trainer
    changes = [e for e in ctx.events if e.verb == "changed trainer"]
    segs = []
    name = changes[0].change_from if changes else (ctx.cp.trainer.full_name if ctx.cp.trainer else None)
    since = ctx.joined
    for e in changes:
        d = _local(e.created_at)
        if name and name != "No trainer":
            segs.append((name, since, d - timedelta(days=1)))
        name, since = e.change_to, d
    for n, a, b in segs:
        rows["trainer"].append(_bar(n, a, b, "old", f"{n} · {_dm(a)} – {_dm(b)}"))
    if ctx.cp.trainer:
        n = ctx.cp.trainer.full_name
        rows["trainer"].append(_bar(n, since, None, "cur", f"{n} · since {_dm(since)}"))
    # Workout
    for pa in ctx.programs:
        p = pa.effective_program
        planned_end = pa.start_date + timedelta(days=p.weeks * 7 - 1)
        if pa.status == "up_next":
            rows["workout"].append(_bar(p.name, pa.start_date, planned_end, "next",
                                        f"{p.name} · from {_dm(pa.start_date)} · up next"))
        elif pa.status == "active":
            week = min(p.weeks, (today - pa.start_date).days // 7 + 1)
            rows["workout"].append(_bar(p.name, pa.start_date, planned_end, "cur",
                                        f"{p.name} · {_dm(pa.start_date)} – {_dm(planned_end)} · week {week} of "
                                        f"{p.weeks}"))
        else:
            end = pa.end_date or pa.start_date
            full = (end - pa.start_date).days + 1 >= p.weeks * 7 - 3
            rows["workout"].append(_bar(p.name, pa.start_date, end, "done" if full else "old",
                                        f"{p.name} · {_dm(pa.start_date)} – {_dm(end)} · "
                                        f"{'completed' if full else 'replaced'}"))
    # Meal plan
    for ma in ctx.meals:
        m = ma.plan
        if ma.status == "up_next":
            rows["meal"].append(_bar(m.name, ma.start_date, None, "next", f"{m.name} · from {_dm(ma.start_date)} · up next"))
        elif ma.status == "active":
            rows["meal"].append(_bar(m.name, ma.start_date, None, "cur", f"{m.name} · since {_dm(ma.start_date)}"))
        else:
            end = ma.end_date or ma.start_date
            rows["meal"].append(_bar(m.name, ma.start_date, end, "done",
                                     f"{m.name} · {_dm(ma.start_date)} – {_dm(end)}"))
    # Supplements
    for sa in ctx.supps:
        n = sa.plan.name
        if sa.active:
            rows["supplements"].append(_bar(n, sa.start_date, None, "cur", f"{n} · since {_dm(sa.start_date)}"))
        else:
            end = _local(sa.updated_at)
            rows["supplements"].append(_bar(n, sa.start_date, end, "old", f"{n} · {_dm(sa.start_date)} – {_dm(end)}"))
    # Habits: the ones on now, as one bar from the first start
    on = [h for h in ctx.habits if h.active]
    if on:
        a = min(h.start_date for h in on)
        names = [h.habit.name for h in on]
        label = names[0] if len(names) == 1 else f"{len(names)} habits"
        rows["habits"].append(_bar(label, a, None, "cur", f"{', '.join(names)} · since {_dm(a)}"))
    # Axis: from the month they joined to at least 4 months ahead (and past anything up next)
    ends = [b["end"] for r in rows.values() for b in r if b["end"]]
    start = date(ctx.joined.year, ctx.joined.month, 1)
    end = max([today + timedelta(days=120), *ends])
    end = date(end.year + (end.month == 12), end.month % 12 + 1, 1) - timedelta(days=1)
    return {"from": start, "to": end, "today": today,
            "rows": [{"key": k, "label": lbl, "bars": rows[k]} for k, lbl in
                     (("trainer", "Trainer"), ("workout", "Workout"), ("meal", "Meal plan"),
                      ("supplements", "Supplements"), ("habits", "Habits"))]}


def _about(ctx):
    cp = ctx.cp
    goals = [e for e in ctx.events if (e.meta or {}).get("history") == "goal"]
    gws = [e for e in ctx.events if (e.meta or {}).get("history") == "goal_weight"]
    changes = [e for e in ctx.events if e.verb == "changed trainer"]
    goal = cp.get_goal_display() if cp.goal else "Not set"
    goal += f" · since {dfmt(_local(goals[-1].created_at), '%b %Y')}" if goals else " · since joining"
    gw = _kg0(cp.target_weight_kg) if cp.target_weight_kg else "Not set"
    if gws:
        gw += f" · was {gws[-1].change_from} until {dfmt(_local(gws[-1].created_at), '%b')}"
    trainer = cp.trainer.full_name if cp.trainer else "No trainer"
    names = {e.change_from for e in changes if e.change_from and e.change_from != "No trainer"} - {trainer}
    if cp.trainer:
        trainer += " · only trainer so far" if not names else f" · before: {', '.join(sorted(names))}"
    return [
        {"label": "Joined", "value": _dy(ctx.joined)},
        {"label": "Came from", "value": _came_from(ctx)},
        {"label": "Goal", "value": goal},
        {"label": "Goal weight", "value": gw},
        {"label": "Target date", "value": "Not set"},
        {"label": "Trainer", "value": trainer},
    ]


def _health(ctx):
    from .models import ClientNote

    cp = ctx.cp
    on = cp.onboarding or {}
    health = on.get("health") or {}
    rows = []
    notes_at = next((_local(e.created_at) for e in reversed(ctx.events) if (e.meta or {}).get("history") == "health"),
                    None)
    for line in [x.strip() for x in (cp.health_notes or "").split("\n") if x.strip()][:4]:
        rows.append({"title": line[:90], "detail": f"Since {_dm(notes_at or ctx.joined)} · from the profile",
                     "tone": "warn"})
    for x in (health.get("injuries") or []) + (health.get("conditions") or []):
        if x and x != "none":
            rows.append({"title": x.replace("_", " ").capitalize(), "detail": f"Since {_dm(ctx.joined)} · from onboarding",
                         "tone": "warn"})
    for n in ClientNote.objects.filter(client=ctx.user, is_flag=True)[:3]:
        rows.append({"title": n.body.strip().split("\n")[0][:90], "detail": f"Flagged {_dm(_local(n.created_at))}",
                     "tone": "warn"})
    if not rows:
        rows.append({"title": "No injuries or conditions", "detail": "From onboarding", "tone": "ok"})
    food = on.get("food") or {}
    bits = [DIETS.get(food.get("diet"), "")]
    avoid = [a for a in (food.get("avoid") or []) if a and a != "none"]
    if avoid:
        bits.append("no " + ", ".join(a.replace("_", " ") for a in avoid))
    line = ", ".join(b for b in bits if b) or "No preferences given"
    sups = [s for s in ctx.supps if s.active]
    if sups:
        line += f" · {sups[0].plan.name.lower()} added in {dfmt(sups[0].start_date, '%b')}"
    rows.append({"title": "Food", "detail": line, "tone": ""})
    return rows


def client_history(user, params):
    ctx = _Ctx(user)
    group = params.get("group") or "all"
    try:
        limit = max(1, min(120, int(params.get("months") or 4)))
    except ValueError:
        limit = 4
    items = [i for i in journey(ctx) if group == "all" or i["group"] == group]
    months = []
    for it in items:
        d = it["date"] or ctx.joined
        key = f"{d.year}-{d.month:02d}"
        if not months or months[-1]["key"] != key:
            months.append({"key": key, "label": dfmt(d, "%B %Y"), "summary": _month_summary(ctx, d.year, d.month),
                           "items": []})
        months[-1]["items"].append({**it, "when": _d(d)})
    return {
        "summary": _summary(ctx),
        "timeline": _timeline(ctx),
        "months": months[:limit],
        "more": len(months) > limit,
        "total_months": len(months),
        "about": _about(ctx),
        "health": _health(ctx),
    }


def history_csv(user):
    from apps.common.export import csv_response

    ctx = _Ctx(user)
    rows = ((dfmt(i["date"] or ctx.joined, "%B %Y"), (i["date"] or ctx.joined).isoformat(), TYPE_LABELS[i["kind"]],
             i["title"], i["detail"], i["who"]) for i in journey(ctx))
    slug = "-".join(user.full_name.lower().split()) or "client"
    return csv_response(f"{slug}-history", ["Month", "Date", "Type", "What", "Details", "Who"], rows)
