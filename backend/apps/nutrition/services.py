from datetime import datetime, timedelta
from decimal import Decimal

from django.db import transaction
from django.db.models import Count, Sum
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from apps.activity.services import log as activity_log
from apps.notifications.services import notify

from .models import (
    Food,
    FoodLogEntry,
    Meal,
    MealDayState,
    MealItem,
    MealOption,
    MealPlan,
    MealPlanAssignment,
    WaterLog,
)


# ---------------------------------------------------------------- plan tree
@transaction.atomic
def sync_meals(plan, meals_data):
    """Make the plan's meals/options/items equal `meals_data` (ids are kept so day states stay linked)."""
    keep_meals = set()
    for mi, md in enumerate(meals_data):
        meal = plan.meals.filter(id=md.get("id")).first() if md.get("id") else None
        meal = meal or Meal(plan=plan)
        meal.name, meal.time = md["name"], md["time"]
        meal.kcal_target = md.get("kcal_target", 0)
        meal.order = mi
        meal.save()
        keep_meals.add(meal.id)
        keep_opts = set()
        opts = md.get("options", [])
        if opts and not any(o.get("is_default") for o in opts):
            opts[0]["is_default"] = True
        seen_default = False
        for oi, od in enumerate(opts):
            opt = meal.options.filter(id=od.get("id")).first() if od.get("id") else None
            opt = opt or MealOption(meal=meal)
            opt.name = od["name"]
            opt.is_default = bool(od.get("is_default")) and not seen_default
            seen_default = seen_default or opt.is_default
            opt.order = oi
            opt.save()
            keep_opts.add(opt.id)
            keep_items = set()
            for ii, idata in enumerate(od.get("items", [])):
                item = opt.items.filter(id=idata.get("id")).first() if idata.get("id") else None
                item = item or MealItem(option=opt)
                item.food = idata["food"]
                item.quantity = idata["quantity"]
                unit = idata.get("unit")
                if unit is not None and unit.food_id != item.food.id:
                    raise ValidationError({"unit": [f"{unit.name} is not a unit of {item.food.name}."]})
                item.unit = unit
                item.order = ii
                item.save()
                keep_items.add(item.id)
            opt.items.exclude(id__in=keep_items).delete()
        meal.options.exclude(id__in=keep_opts).delete()
    plan.meals.exclude(id__in=keep_meals).delete()
    if plan.status == MealPlan.Status.PUBLISHED:
        plan.has_unpublished_changes = True
    plan.save(update_fields=["has_unpublished_changes", "updated_at"])
    return plan


@transaction.atomic
def duplicate_plan(src, *, actor):
    dst = MealPlan.objects.create(
        name=f"{src.name} (copy)"[:120], diet=src.diet, kcal_target=src.kcal_target, protein_g=src.protein_g,
        carbs_g=src.carbs_g, fat_g=src.fat_g, fibre_g=src.fibre_g, water_ml=src.water_ml,
        allow_swaps=src.allow_swaps, allow_search_any=src.allow_search_any,
        allow_switch_options=src.allow_switch_options, allow_off_plan=src.allow_off_plan, created_by=actor,
    )
    for m in src.meals.prefetch_related("options__items"):
        nm = Meal.objects.create(plan=dst, name=m.name, time=m.time, kcal_target=m.kcal_target, order=m.order)
        for o in m.options.all():
            no = MealOption.objects.create(meal=nm, name=o.name, is_default=o.is_default, order=o.order)
            MealItem.objects.bulk_create([MealItem(option=no, food_id=i.food_id, quantity=i.quantity,
                                                   unit_id=i.unit_id, order=i.order) for i in o.items.all()])
    return dst


DEFAULT_SPLIT = [("Breakfast", "08:00", 0.25), ("Lunch", "13:30", 0.30), ("Snack", "17:00", 0.12),
                 ("Dinner", "20:30", 0.33)]


@transaction.atomic
def new_plan(*, name, diet, kcal_target, actor):
    """'Breakfast, Lunch, Snack and Dinner split this target.'"""
    p = MealPlan.objects.create(name=name, diet=diet, kcal_target=kcal_target, created_by=actor,
                                protein_g=round(kcal_target * 0.25 / 4), carbs_g=round(kcal_target * 0.45 / 4),
                                fat_g=round(kcal_target * 0.30 / 9))
    label = dict(MealPlan._meta.get_field("diet").choices).get(diet, "Main")
    for i, (n, t, share) in enumerate(DEFAULT_SPLIT):
        m = Meal.objects.create(plan=p, name=n, time=t, kcal_target=round(kcal_target * share / 10) * 10, order=i)
        MealOption.objects.create(meal=m, name=label.split()[0], is_default=True)
    return p


@transaction.atomic
def set_plan_clients(plan, client_ids, *, actor):
    from apps.clients.services import visible_clients

    current = set(MealPlanAssignment.objects.filter(plan=plan, status="active").values_list("client_id", flat=True))
    wanted = set(client_ids)
    added, removed = wanted - current, current - wanted
    clients = list(visible_clients(actor).filter(id__in=added))
    today = timezone.localdate()
    for c in clients:
        # "Clients on another meal plan move to this one. Their logged meals stay."
        MealPlanAssignment.objects.filter(client=c, status="active").update(status="ended", end_date=today)
        MealPlanAssignment.objects.create(client=c, plan=plan, start_date=today, assigned_by=actor)
        activity_log("assigned a meal plan", "plan", actor=actor, target=c, target_label=plan.name, client=c)
    if clients and plan.status == MealPlan.Status.PUBLISHED:
        notify(clients, "meal_plan_assigned", f"New meal plan: {plan.name}", "Open Food to see today's meals.",
               actor=actor, data={"route": "/food"})
    if removed:
        MealPlanAssignment.objects.filter(plan=plan, status="active", client_id__in=removed).update(
            status="ended", end_date=today)
    return len(clients), len(removed)


@transaction.atomic
def publish(plan, *, actor):
    plan.status = MealPlan.Status.PUBLISHED
    plan.published_at = timezone.now()
    plan.has_unpublished_changes = False
    plan.save(update_fields=["status", "published_at", "has_unpublished_changes", "updated_at"])
    rows = list(MealPlanAssignment.objects.filter(plan=plan, status="active").select_related(
        "client__client_profile__trainer"))
    clients = [a.client for a in rows]
    if clients:
        notify(clients, "meal_plan_updated", f"{plan.name} was updated", "Open Food to see your meals.",
               actor=actor, data={"route": "/food"})
    trainers = {a.client.client_profile.trainer for a in rows if a.client.client_profile.trainer}
    trainers.discard(actor)
    if trainers:
        notify(list(trainers), "meal_plan_updated", f"{plan.name} was published",
               f"{len(clients)} clients get the new version.", actor=actor, data={"route": f"/meal-plans/{plan.id}"})
    activity_log("published a meal plan", "plan", actor=actor, target=plan, target_label=plan.name,
                 meta={"clients": len(clients)})
    return len(clients)


# ---------------------------------------------------------------- the client's day
def _grams(item, quantity=None):
    q = Decimal(str(quantity)) if quantity is not None else item.quantity
    return q * (item.unit.grams if item.unit else Decimal(1))


def _entry_for_item(client, day, meal, item, state, now):
    """FoodLogEntry for one planned food, with today's portion and swap applied."""
    key = str(item.id)
    qty = state.portions.get(key) if state else None
    swap = state.swaps.get(key) if state else None
    food, grams, swapped_from = item.food, _grams(item, qty), ""
    unit_name = item.unit.name if item.unit else "g"
    quantity = Decimal(str(qty)) if qty is not None else item.quantity
    if swap:
        alt = Food.objects.filter(id=swap.get("food")).first()
        if alt:
            swapped_from = food.name
            food = alt
            grams = Decimal(str(swap.get("grams") or grams))
            quantity, unit_name = grams, "g"
    m = food.per_grams(grams)
    return FoodLogEntry(client=client, date=day, logged_at=now, meal_name=meal.name, meal=meal, food=food,
                        name=food.name, quantity=quantity, unit_name=unit_name, grams=grams, kcal=m["kcal"],
                        protein=m["protein"], carbs=m["carbs"], fat=m["fat"], source=FoodLogEntry.Source.PLAN,
                        swapped_from=swapped_from)


def _option_for(meal, state):
    if state and state.option_id:
        return state.option
    return next((o for o in meal.options.all() if o.is_default), None) or meal.options.first()


@transaction.atomic
def mark_eaten(client, meal, day, photo=None):
    """Logs a planned meal. [photo] (optional) is a picture of what was eaten."""
    state, _ = MealDayState.objects.get_or_create(client=client, date=day, meal=meal)
    if photo is not None:
        if state.photo:
            state.photo.delete(save=False)
        state.photo = photo
        state.save(update_fields=["photo", "updated_at"])
    if state.status == MealDayState.Status.LOGGED:
        return state
    opt = _option_for(meal, state)
    now = timezone.now()
    FoodLogEntry.objects.filter(client=client, date=day, meal=meal, source=FoodLogEntry.Source.PLAN).delete()
    FoodLogEntry.objects.bulk_create([_entry_for_item(client, day, meal, it, state, now)
                                      for it in opt.items.select_related("food", "unit")] if opt else [])
    state.status = MealDayState.Status.LOGGED
    state.option = opt
    state.logged_at = now
    state.save()
    return state


@transaction.atomic
def unmark(client, meal, day):
    state = MealDayState.objects.filter(client=client, date=day, meal=meal).first()
    if state:
        FoodLogEntry.objects.filter(client=client, date=day, meal=meal, source=FoodLogEntry.Source.PLAN).delete()
        state.status = ""
        state.logged_at = None
        if state.photo:
            state.photo.delete(save=False)
        state.photo = None
        state.save(update_fields=["status", "logged_at", "photo", "updated_at"])
    return state


def skip(client, meal, day):
    state, _ = MealDayState.objects.get_or_create(client=client, date=day, meal=meal)
    FoodLogEntry.objects.filter(client=client, date=day, meal=meal, source=FoodLogEntry.Source.PLAN).delete()
    state.status = MealDayState.Status.SKIPPED
    state.save(update_fields=["status", "updated_at"])
    return state


def log_food(client, *, meal_name, food=None, quantity=1, unit=None, name="", kcal=None, protein=0, carbs=0,
             fat=0, day=None, off_plan=False, reason="", other_time=False):
    """[off_plan]: the client ticked "Off-plan meal" (party, eating out), so the entry is marked for the coach.
    [other_time]: eaten outside the meal times ("Other time" in Add to); always off-plan, kept out of meal cards."""
    day = day or timezone.localdate()
    off_plan = off_plan or other_time
    mp = _active_plan(client, day)
    if food is not None:
        grams = Decimal(str(quantity)) * (unit.grams if unit else Decimal(1))
        m = food.per_grams(grams)
        planned_ids = set(MealItem.objects.filter(option__meal__plan=mp.plan).values_list("food_id", flat=True)) \
            if mp else set()
        if mp and not mp.plan.allow_off_plan and food.id not in planned_ids:
            raise ValidationError("Your plan does not allow food outside it. Tell your coach in your check-in.")
        return FoodLogEntry.objects.create(
            client=client, date=day, meal_name=meal_name, food=food, name=food.name, quantity=quantity,
            unit_name=unit.name if unit else "g", grams=grams, kcal=m["kcal"], protein=m["protein"],
            carbs=m["carbs"], fat=m["fat"], reason=reason if off_plan else "", other_time=other_time,
            source=FoodLogEntry.Source.PLAN if food.id in planned_ids and not off_plan
            else FoodLogEntry.Source.OFF_PLAN)
    return FoodLogEntry.objects.create(client=client, date=day, meal_name=meal_name, name=name or "Quick add",
                                       quantity=1, unit_name="serving", kcal=kcal, protein=protein or 0,
                                       carbs=carbs or 0, fat=fat or 0, reason=reason if off_plan else "",
                                       other_time=other_time,
                                       source=FoodLogEntry.Source.OFF_PLAN if off_plan
                                       else FoodLogEntry.Source.QUICK_ADD)


def _same_time(at, day, now):
    """An "Other time" entry copied to [day] keeps its clock time (never later than now)."""
    local = timezone.localtime(at)
    return min(timezone.make_aware(datetime.combine(day, local.time().replace(tzinfo=None))), now)


def copy_yesterday(client, day=None):
    """Copies yesterday's food log to [day]. A plan meal already logged today is not copied twice.
    Returns (new entries, ids of the plan meals it marked as logged) so the app can Undo it."""
    day = day or timezone.localdate()
    logged = set(MealDayState.objects.filter(client=client, date=day, status=MealDayState.Status.LOGGED)
                 .values_list("meal_id", flat=True))
    rows = [r for r in FoodLogEntry.objects.filter(client=client, date=day - timedelta(days=1))
            if not (r.source == FoodLogEntry.Source.PLAN and r.meal_id in logged)]
    now = timezone.now()
    new = FoodLogEntry.objects.bulk_create([
        FoodLogEntry(client=client, date=day, logged_at=_same_time(r.logged_at, day, now) if r.other_time else now,
                     meal_name=r.meal_name, meal=r.meal, food=r.food,
                     name=r.name, quantity=r.quantity, unit_name=r.unit_name, grams=r.grams, kcal=r.kcal,
                     protein=r.protein, carbs=r.carbs, fat=r.fat, source=r.source, swapped_from=r.swapped_from,
                     reason=r.reason, other_time=r.other_time)
        for r in rows])
    meals = sorted({r.meal_id for r in rows if r.meal_id and r.source == FoodLogEntry.Source.PLAN})
    for meal_id in meals:
        MealDayState.objects.update_or_create(client=client, date=day, meal_id=meal_id,
                                              defaults={"status": "logged", "logged_at": now})
    return new, meals


@transaction.atomic
def undo_copy(client, ids, meals, day=None):
    """Undo of Copy yesterday: removes those entries and un-logs the plan meals the copy logged."""
    day = day or timezone.localdate()
    n, _ = FoodLogEntry.objects.filter(client=client, date=day, id__in=ids).delete()
    for st in MealDayState.objects.filter(client=client, date=day, meal_id__in=meals,
                                          status=MealDayState.Status.LOGGED):
        if not FoodLogEntry.objects.filter(client=client, date=day, meal_id=st.meal_id,
                                           source=FoodLogEntry.Source.PLAN).exists():
            st.status, st.logged_at = "", None
            st.save(update_fields=["status", "logged_at", "updated_at"])
    return n


def _active_plan(client, day):
    return (MealPlanAssignment.objects.filter(client=client, status="active", start_date__lte=day)
            .select_related("plan").order_by("-start_date").first())


def totals(client, day):
    agg = FoodLogEntry.objects.filter(client=client, date=day).aggregate(
        kcal=Sum("kcal"), protein=Sum("protein"), carbs=Sum("carbs"), fat=Sum("fat"))
    return {k: float(v or 0) for k, v in agg.items()}


def add_water(client, ml, day=None):
    day = day or timezone.localdate()
    w, _ = WaterLog.objects.get_or_create(client=client, date=day)
    w.ml = max(0, min(10000, w.ml + int(ml)))
    w.save(update_fields=["ml", "updated_at"])
    sync_water_habit(client, day, w.ml)
    return w


def sync_water_habit(client, day, ml):
    """A water habit counted in glasses follows the water log (one glass = 250 ml), so the Home
    water card and the habit row never disagree."""
    from apps.habits.models import Habit, HabitAssignment, HabitLog

    for a in HabitAssignment.objects.filter(client=client, active=True, start_date__lte=day,
                                            habit__icon="water", habit__kind=Habit.Kind.COUNTER,
                                            habit__deleted_at__isnull=True).select_related("habit"):
        h = a.habit
        value = ml if h.unit.strip().lower() == "ml" else ml // 250
        HabitLog.objects.update_or_create(habit=h, client=client, date=day,
                                          defaults={"value": value, "done": bool(h.target) and value >= h.target})


def pill_for(meal, state, day, now):
    """Logged / Next / To log / Planned / Missed / Skipped."""
    today = timezone.localdate()
    if state and state.status == "logged":
        return "logged"
    if state and state.status == "skipped":
        return "skipped"
    if day > today:
        return "planned"
    if day < today:
        return "missed"
    meal_dt = timezone.make_aware(datetime.combine(day, meal.time))
    if meal_dt <= now:
        return "to_log"
    return "next"


def day_view(client, day, request=None):
    """Food tab: ring, plan meals with pills, food log, water, week bars."""
    def url(f):
        return (request.build_absolute_uri(f.url) if request else f.url) if f else None

    today = timezone.localdate()
    now = timezone.localtime()
    mp = _active_plan(client, day)
    plan = mp.plan if mp else None
    states = {s.meal_id: s for s in MealDayState.objects.filter(client=client, date=day).select_related("option")}
    meals = []
    next_marked = False
    if plan:
        for meal in plan.meals.prefetch_related("options__items__food__units", "options__items__unit"):
            st = states.get(meal.id)
            opt = _option_for(meal, st)
            pill = pill_for(meal, st, day, now)
            if pill == "next":
                if next_marked:
                    pill = "planned"
                next_marked = True
            items = []
            apply_today = day == today  # swaps/portions only apply to today
            for it in (opt.items.all() if opt else []):
                e = _entry_for_item(client, day, meal, it, st if apply_today else None, now)
                items.append({"item": it.id, "food": e.food_id, "name": e.name, "quantity": float(e.quantity),
                              "unit": e.unit_name, "grams": float(e.grams), "kcal": e.kcal,
                              "protein": float(e.protein), "carbs": float(e.carbs), "fat": float(e.fat),
                              "swapped_from": e.swapped_from, "swaps": it.food.swaps.count(),
                              "planned_quantity": float(it.quantity)})
            meals.append({
                "id": meal.id, "name": meal.name, "time": meal.time, "kcal_target": meal.kcal_target, "pill": pill,
                "option": opt.id if opt else None,
                "options": [{"id": o.id, "name": o.name, "is_default": o.is_default} for o in meal.options.all()],
                "items": items, "kcal": sum(i["kcal"] for i in items),
                "protein": round(sum(i["protein"] for i in items), 1), "carbs": round(sum(i["carbs"] for i in items), 1),
                "fat": round(sum(i["fat"] for i in items), 1),
                "logged_at": st.logged_at if st else None, "photo": url(st.photo) if st else None,
            })
    entries = list(FoodLogEntry.objects.filter(client=client, date=day).order_by("logged_at"))
    eaten = totals(client, day)
    target = plan.kcal_target if plan else None
    planned_total = sum(m["kcal"] for m in meals)
    still_ahead = sum(m["kcal"] for m in meals if m["pill"] in ("next", "planned", "to_log"))
    water = WaterLog.objects.filter(client=client, date=today).first()
    monday = day - timedelta(days=day.weekday())
    week = []
    n_meals = plan.meals.count() if plan else 0
    logged = {}
    for d, n in (MealDayState.objects.filter(client=client, date__range=(monday, monday + timedelta(days=6)),
                                             status=MealDayState.Status.LOGGED)
                 .values_list("date").annotate(n=Count("id"))):
        logged[d] = n
    for i in range(7):
        d = monday + timedelta(days=i)
        week.append({"date": d, **totals(client, d), "meals_logged": logged.get(d, 0), "meals": n_meals,
                     "done": n_meals > 0 and logged.get(d, 0) >= n_meals})
    photos = {m["id"]: m["photo"] for m in meals if m.get("photo")}
    coach = getattr(getattr(client, "client_profile", None), "trainer", None)
    return {
        "date": day, "today": day == today, "can_log": day == today,
        "coach": coach.first_name if coach else "",
        "plan": {"id": plan.id, "name": plan.name, "kcal": plan.kcal_target, "protein": plan.protein_g,
                 "carbs": plan.carbs_g, "fat": plan.fat_g, "fibre": plan.fibre_g, "water_ml": plan.water_ml,
                 "version_note": mp.version_note, "allow_swaps": plan.allow_swaps,
                 "allow_search_any": plan.allow_search_any, "allow_switch_options": plan.allow_switch_options,
                 "allow_off_plan": plan.allow_off_plan} if plan else None,
        "ring": {"target": target, "eaten": eaten["kcal"], "left": max((target or 0) - eaten["kcal"], 0),
                 "planned": planned_total, "still_ahead": still_ahead},
        "macros": eaten,
        "meals": meals,
        "log": [{"id": e.id, "time": e.logged_at, "meal_name": e.meal_name, "meal": e.meal_id, "name": e.name,
                 "quantity": float(e.quantity), "unit": e.unit_name, "kcal": e.kcal, "protein": float(e.protein),
                 "carbs": float(e.carbs), "fat": float(e.fat), "source": e.source, "food": e.food_id,
                 "grams": float(e.grams) if e.grams is not None else None, "reason": e.reason,
                 "photo": photos.get(e.meal_id) if e.source == "plan" else None,
                 "swapped_from": e.swapped_from, "other_time": e.other_time} for e in entries],
        "water": {"ml": water.ml if water else 0, "goal_ml": plan.water_ml if plan else 3000},
        "week": week,
    }


# ---------------------------------------------------------------- one client's meal plans (client profile → Plans)
@transaction.atomic
def assign_plan_to_client(client, plan, *, actor, start_date=None, notify_client=True):
    """Client profile → Assign a meal plan. From today: the current plan ends today and moves to history.
    A later date: the plan waits as Up next and replaces the current one on that day (see `roll_meal_plans`)."""
    today = timezone.localdate()
    if plan is None or plan.deleted_at is not None:
        raise ValidationError({"plan": ["Pick a meal plan."]})
    if start_date and start_date > today + timedelta(days=92):
        raise ValidationError({"start_date": ["Pick a date up to 3 months ahead."]})
    later = bool(start_date and start_date > today)
    if later:
        MealPlanAssignment.objects.filter(client=client, status="up_next").update(status="ended", end_date=today)
    else:
        MealPlanAssignment.objects.filter(client=client, status="active").update(status="ended", end_date=today)
    a = MealPlanAssignment.objects.create(client=client, plan=plan, start_date=start_date if later else today,
                                          status="up_next" if later else "active", assigned_by=actor)
    activity_log("assigned a meal plan", "plan", actor=actor, target=client, target_label=plan.name, client=client)
    if notify_client and not later and plan.status == MealPlan.Status.PUBLISHED:
        notify(client, "meal_plan_assigned", f"New meal plan: {plan.name}", "Open Food to see today's meals.",
               actor=actor, data={"route": "/food"})
    return a


def end_client_plan(a, *, actor):
    a.status = "ended"
    a.end_date = timezone.localdate()
    a.save(update_fields=["status", "end_date", "updated_at"])
    activity_log("ended a meal plan", "plan", actor=actor, target=a.client, target_label=a.plan.name, client=a.client)


def roll_meal_plans(today=None):
    """Daily: an Up next meal plan whose day has come replaces the current one. Returns how many started."""
    today = today or timezone.localdate()
    n = 0
    for a in MealPlanAssignment.objects.filter(status="up_next", start_date__lte=today).select_related("client", "plan"):
        MealPlanAssignment.objects.filter(client=a.client, status="active").update(status="ended",
                                                                                  end_date=today - timedelta(days=1))
        a.status = "active"
        a.save(update_fields=["status", "updated_at"])
        notify(a.client, "meal_plan_assigned", f"New meal plan: {a.plan.name}", "It starts today.",
               data={"route": "/food"})
        n += 1
    return n


def staff_food_log(client, params):
    """Client profile → Logs → Meals table: one row per day of the range, newest first, with the day's
    totals, meals logged of the plan's meals, and On plan / Over / Partly / Missed."""
    from apps.clients.logs import days_desc, page_of
    from apps.clients.metrics import resolve_range

    start, end = resolve_range(params, client)
    today = timezone.localdate()
    days = days_desc(start, end, client)
    mps = list(MealPlanAssignment.objects.filter(client=client, start_date__lte=end)
               .select_related("plan").order_by("-start_date"))

    def plan_on(d):
        return next((m.plan for m in mps if m.start_date <= d and (m.end_date is None or m.end_date >= d)), None)

    logged = dict(MealDayState.objects.filter(client=client, date__range=(start, end), status=MealDayState.Status.LOGGED)
                  .values_list("date").annotate(n=Count("id")))
    sums = {r["date"]: r for r in FoodLogEntry.objects.filter(client=client, date__range=(start, end))
            .values("date").annotate(kcal=Sum("kcal"), protein=Sum("protein"), carbs=Sum("carbs"), fat=Sum("fat"))}
    n_meals = {}
    rows = []
    for d in days:
        plan = plan_on(d)
        if plan is not None and plan.id not in n_meals:
            n_meals[plan.id] = plan.meals.count()
        meals = n_meals.get(plan.id, 0) if plan else 0
        t = sums.get(d) or {}
        kcal = int(t.get("kcal") or 0)
        n = logged.get(d, 0)
        if not plan and not t:
            continue
        target = plan.kcal_target if plan else None
        if target and kcal > target * 1.05:
            st = "over"
        elif meals and n >= meals:
            st = "on_plan"
        elif n or kcal:
            st = "today" if d == today else ("partly" if meals else "logged")
        else:
            st = "today" if d == today else "missed"
        rows.append({"date": d, "kcal": kcal, "protein": float(t.get("protein") or 0), "carbs": float(t.get("carbs") or 0),
                     "fat": float(t.get("fat") or 0), "meals_logged": n, "meals": meals, "kcal_target": target,
                     "status": st})
    cur = plan_on(min(end, today)) or (mps[0].plan if mps else None)
    out = page_of(rows, params)
    out["target"] = {"kcal": cur.kcal_target, "protein": cur.protein_g, "carbs": cur.carbs_g, "fat": cur.fat_g} \
        if cur else None
    return out
