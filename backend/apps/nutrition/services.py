import logging
from datetime import datetime, timedelta
from decimal import Decimal

from django.db import transaction
from django.db.models import Count, Sum
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from apps.common.calc import food_macros, nutrition_totals, show_g, show_kcal
from apps.activity.services import log as activity_log
from apps.notifications.services import notify

from . import swaps
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
    meals_on,
)


logger = logging.getLogger(__name__)


# ---------------------------------------------------------------- plan tree
@transaction.atomic
def sync_meals(plan, meals_data):
    """Make the plan's meals/options/items equal `meals_data` (ids are kept so day states stay linked)."""
    _sync_set(plan, plan.meals.all(), meals_data, None)
    if plan.status == MealPlan.Status.PUBLISHED:
        plan.has_unpublished_changes = True
    plan.save(update_fields=["has_unpublished_changes", "updated_at"])
    return plan


def _sync_set(plan, meals, meals_data, weekday):
    """Make one set of meals (`meals`: every-day ones, or one weekday's) equal `meals_data`."""
    keep_meals = set()
    for mi, md in enumerate(meals_data):
        meal = meals.filter(id=md.get("id")).first() if md.get("id") else None
        meal = meal or Meal(plan=plan)
        meal.weekday = weekday
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
                if "swaps" in idata:
                    item.alternatives = swaps.clean(item.food, idata["swaps"])
                elif item.pk is None and not plan.is_master:
                    item.alternatives = swaps.seed_from_food(item)  # a food added to a client's copy
                item.save()
                keep_items.add(item.id)
            opt.items.exclude(id__in=keep_items).delete()
        meal.options.exclude(id__in=keep_opts).delete()
    meals.exclude(id__in=keep_meals).delete()


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
                                                   unit_id=i.unit_id, order=i.order, alternatives=i.alternatives)
                                          for i in o.items.all()])
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


def can_edit_meal_plan(user, plan):
    """Same rule as programs (D-39): Vimal changes every master plan; a trainer changes one with "Edit gym
    templates", or one they made themselves when they may make meal plans."""
    if user.is_admin:
        return True
    if not user.is_trainer:
        return False
    tp = user.trainer_profile
    if tp.has_perm("training.edit_templates"):
        return True
    return plan.created_by_id == user.id and tp.has_perm("nutrition.meal_plans")


def _end_current(client, *, today):
    """The client's running meal plan ends today because another one takes over. Returns it (or None)."""
    cur = MealPlanAssignment.objects.filter(client=client, status="active").first()
    if cur is not None:
        cur.status, cur.end_date, cur.end_reason = "ended", today, "replaced"
        cur.save(update_fields=["status", "end_date", "end_reason", "updated_at"])
    return cur


@transaction.atomic
def set_plan_clients(plan, client_ids, *, actor):
    """Assign drawer: the plan's followers become exactly `client_ids`. Only clients this person can see are
    touched, so a trainer never takes the plan away from another trainer's clients."""
    from apps.clients.services import visible_clients

    visible = visible_clients(actor)
    current = set(MealPlanAssignment.objects.filter(plan=plan, status="active", client__in=visible)
                  .values_list("client_id", flat=True))
    wanted = {str(c) for c in client_ids}
    current_s = {str(c) for c in current}
    added, removed = wanted - current_s, current_s - wanted
    clients = list(visible.filter(id__in=added))
    today = timezone.localdate()
    for c in clients:
        # "Clients on another meal plan move to this one. Their logged meals stay."
        prev = _end_current(c, today=today)
        MealPlanAssignment.objects.create(client=c, plan=plan, start_date=today, assigned_by=actor, replaced=prev)
        activity_log("assigned a meal plan", "plan", actor=actor, target=c, target_label=plan.name, client=c)
    if clients and plan.status == MealPlan.Status.PUBLISHED:
        notify(clients, "meal_plan_assigned", f"New meal plan: {plan.name}", "Open Food to see today's meals.",
               actor=actor, data={"route": "/food"})
    for a in MealPlanAssignment.objects.filter(plan=plan, status="active", client_id__in=removed):
        unassign(a)
    return len(clients), len(removed)


def unassign(a):
    """Take a client off a meal plan. Assigned and taken off the same day with nothing logged (an Undo, a slip):
    it never really ran, so it leaves no Plan history row and the plan it replaced comes back (D-43). Otherwise it
    moves to Plan history as Unassigned."""
    today = timezone.localdate()
    logged = (MealDayState.objects.filter(client=a.client, date__gte=a.start_date, meal__plan__in=[
        p for p in (a.plan_id, a.custom_plan_id) if p]).exclude(status="").exists()
        or FoodLogEntry.objects.filter(client=a.client, date__gte=a.start_date, meal__plan_id__in=[
            p for p in (a.plan_id, a.custom_plan_id) if p]).exists())
    if timezone.localtime(a.created_at).date() == timezone.localdate() and not logged:  # gym time, not UTC
        prev, custom = a.replaced, a.custom_plan
        a.delete()
        if custom is not None:
            custom.soft_delete()
        if prev is not None and prev.status == "ended" and prev.end_date == today \
                and not MealPlanAssignment.objects.filter(client=prev.client, status="active").exists():
            prev.status, prev.end_reason, prev.end_date = "active", "", None
            prev.save(update_fields=["status", "end_reason", "end_date", "updated_at"])
        return
    a.status, a.end_date, a.end_reason = "ended", today, "unassigned"
    a.save(update_fields=["status", "end_date", "end_reason", "updated_at"])


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
               f"{len(clients)} clients get the new version.", actor=actor, data={"route": f"/nutrition/{plan.id}"})
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
    m = food_macros(food, grams)
    return FoodLogEntry(client=client, date=day, logged_at=now, meal_name=meal.name, meal=meal, meal_item=item, food=food,
                        name=food.name, quantity=quantity, unit_name=unit_name, grams=grams, kcal=m["kcal"],
                        protein=m["protein"], carbs=m["carbs"], fat=m["fat"], source=FoodLogEntry.Source.PLAN,
                        swapped_from=swapped_from)


def _option_for(meal, state):
    if state and state.option_id:
        return state.option
    return next((o for o in meal.options.all() if o.is_default), None) or meal.options.first()


def _plan_entries(client, day, meal):
    return FoodLogEntry.objects.filter(client=client, date=day, meal=meal, source=FoodLogEntry.Source.PLAN)


def _settle(state, items):
    """Meal status from its foods: every food decided → logged (something eaten) or skipped (nothing eaten)."""
    ids = [str(it.id) for it in items]
    got = [state.items.get(i) for i in ids]
    if ids and all(got):
        state.status = MealDayState.Status.LOGGED if "eaten" in got else MealDayState.Status.SKIPPED
        state.logged_at = state.logged_at or timezone.now() if "eaten" in got else None
    else:
        state.status = ""
        if "eaten" not in got:
            state.logged_at = None


def _write_entries(client, day, meal, state, items, now=None):
    """One plan entry for every food marked eaten (with today's portion and swap); none for the others."""
    now = now or timezone.now()
    _plan_entries(client, day, meal).delete()
    FoodLogEntry.objects.bulk_create([_entry_for_item(client, day, meal, it, state, now) for it in items
                                      if state.items.get(str(it.id)) == "eaten"])


def _items(meal, state):
    opt = _option_for(meal, state)
    items = list(opt.items.select_related("food", "unit")) if opt else []
    if state is not None and not state.items and state.status:  # logged / skipped before foods had their own state
        state.items = {str(it.id): "eaten" if state.status == MealDayState.Status.LOGGED else "skipped" for it in items}
    return opt, items


def add_meal_photo(state, photo):
    """The first picture goes in `photo`, the next ones in MealPhoto, up to MAX_PHOTOS in all."""
    from .models import MealPhoto

    if not state.photo:
        state.photo = photo
        state.save(update_fields=["photo", "updated_at"])
        return
    if 1 + state.more_photos.count() >= MealDayState.MAX_PHOTOS:
        raise ValidationError({"photo": [f"A meal can have up to {MealDayState.MAX_PHOTOS} photos."]})
    MealPhoto.objects.create(state=state, image=photo)


def remove_meal_photos(state):
    for p in state.more_photos.all():
        p.image.delete(save=False)
        p.delete()
    if state.photo:
        state.photo.delete(save=False)
    state.photo = None


@transaction.atomic
def mark_eaten(client, meal, day, photo=None):
    """Logs a planned meal: every food not skipped on its own is eaten. [photo] (optional): a picture of it."""
    state, _ = MealDayState.objects.get_or_create(client=client, date=day, meal=meal)
    if photo is not None:
        add_meal_photo(state, photo)
    if state.status == MealDayState.Status.LOGGED:
        return state
    opt, items = _items(meal, state)
    for it in items:
        if state.items.get(str(it.id)) != "skipped":
            state.items[str(it.id)] = "eaten"
    if items and all(state.items.get(str(it.id)) == "skipped" for it in items):  # all skipped one by one: eat all
        state.items = {str(it.id): "eaten" for it in items}
    _write_entries(client, day, meal, state, items)
    state.status = MealDayState.Status.LOGGED
    state.option = opt
    state.logged_at = timezone.now()
    state.save()
    return state


@transaction.atomic
def unmark(client, meal, day):
    """Undo: the meal and every food in it go back to "not logged yet"."""
    state = MealDayState.objects.filter(client=client, date=day, meal=meal).first()
    if state:
        _plan_entries(client, day, meal).delete()
        state.status = ""
        state.items = {}
        state.logged_at = None
        remove_meal_photos(state)
        state.save(update_fields=["status", "items", "logged_at", "photo", "updated_at"])
    return state


@transaction.atomic
def skip(client, meal, day):
    """Skip the whole meal: every food skipped, nothing counts. It stays skipped until she logs it herself."""
    state, _ = MealDayState.objects.get_or_create(client=client, date=day, meal=meal)
    _, items = _items(meal, state)
    _plan_entries(client, day, meal).delete()
    state.items = {str(it.id): "skipped" for it in items}
    state.status = MealDayState.Status.SKIPPED
    state.logged_at = None
    state.save(update_fields=["status", "items", "logged_at", "updated_at"])
    return state


@transaction.atomic
def item_action(client, meal, day, item, action):
    """One planned food: eat | skip | reset (back to "not logged yet"). The meal's status follows its foods."""
    state, _ = MealDayState.objects.get_or_create(client=client, date=day, meal=meal)
    opt, items = _items(meal, state)
    if item.id not in {it.id for it in items}:
        raise ValidationError({"item": ["This food is not in today's meal."]})
    key = str(item.id)
    if action == "eat":
        state.items[key] = "eaten"
    elif action == "skip":
        state.items[key] = "skipped"
    elif action == "reset":
        state.items.pop(key, None)
    else:
        raise ValidationError({"action": ["Use eat, skip or reset."]})
    state.option = state.option or opt
    _write_entries(client, day, meal, state, items)
    _settle(state, items)
    state.save()
    return state


@transaction.atomic
def forget_item(client, entry):
    """A logged planned food deleted from the log: its entry goes and the food is "not logged yet" again."""
    state = MealDayState.objects.filter(client=client, date=entry.date, meal_id=entry.meal_id).first()
    entry.delete()
    if state is None:
        return
    _, items = _items(entry.meal, state)
    state.items.pop(str(entry.meal_item_id), None)
    _settle(state, items)
    state.save()


@transaction.atomic
def rewrite_eaten(client, meal, day, state):
    """After a portion or swap change: the eaten foods' entries follow the new amounts, the states stay."""
    _, items = _items(meal, state)
    _write_entries(client, day, meal, state, items)


def _check_macros(name, kcal, protein, carbs, fat):
    """Phase 3.2: kcal should match 4 × protein + 4 × carbs + 9 × fat. A mismatch is logged, never refused."""
    from apps.common.calc import kcal_from_macros, macros_match

    if kcal is not None and (protein or carbs or fat) and not macros_match(kcal, protein, carbs, fat):
        logger.warning("Food kcal does not match its macros: %s · %s kcal stated, %.0f kcal from 4P+4C+9F",
                       name, kcal, kcal_from_macros(protein, carbs, fat))


def log_food(client, *, meal_name, food=None, quantity=1, unit=None, name="", kcal=None, protein=0, carbs=0,
             fat=0, day=None, off_plan=False, reason="", other_time=False):
    """[off_plan]: the client ticked "Off-plan meal" (party, eating out), so the entry is marked for the coach.
    [other_time]: eaten outside the meal times ("Other time" in Add to); always off-plan, kept out of meal cards."""
    day = day or timezone.localdate()
    off_plan = off_plan or other_time
    mp = _active_plan(client, day)
    if mp and not other_time:  # adding to a planned meal waits until it opens, like logging it (Probid 2026-10-30)
        meal = next((m for m in meals_on(mp.followed, day.weekday()) if m.name == meal_name), None)
        if meal is not None:
            check_meal_open(meal, day)
    if food is not None:
        grams = Decimal(str(quantity)) * (unit.grams if unit else Decimal(1))
        m = food_macros(food, grams)
        # the plan the client follows: their own copy, else the master
        planned_ids = set(MealItem.objects.filter(option__meal__plan=mp.followed).values_list("food_id", flat=True)) \
            if mp else set()
        if mp and not mp.followed.allow_off_plan and food.id not in planned_ids:
            raise ValidationError("Your plan does not allow food outside it. Tell your coach in your check-in.")
        _check_macros(food.name, food.kcal, food.protein, food.carbs, food.fat)
        return FoodLogEntry.objects.create(
            client=client, date=day, meal_name=meal_name, food=food, name=food.name, quantity=quantity,
            unit_name=unit.name if unit else "g", grams=grams, kcal=m["kcal"], protein=m["protein"],
            carbs=m["carbs"], fat=m["fat"], reason=reason if off_plan else "", other_time=other_time,
            source=FoodLogEntry.Source.PLAN if food.id in planned_ids and not off_plan
            else FoodLogEntry.Source.OFF_PLAN)
    _check_macros(name or "Quick add", kcal, protein, carbs, fat)
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
    # A client copy can have other meals on another weekday: a plan meal of yesterday goes to today's meal
    # of the same name (or stays as it was when today has the same meals).
    mp = _active_plan(client, day)
    todays = {m.name.lower(): m.id for m in meals_on(mp.followed, day.weekday())} if mp else {}
    ids = set(todays.values())

    def meal_today(r):
        if r.meal_id is None or r.meal_id in ids or not todays:
            return r.meal_id
        return todays.get(r.meal_name.lower(), r.meal_id)

    rows = [r for r in FoodLogEntry.objects.filter(client=client, date=day - timedelta(days=1))
            if not (r.source == FoodLogEntry.Source.PLAN and meal_today(r) in logged)]
    for r in rows:
        r.meal_id = meal_today(r)
    now = timezone.now()
    new = FoodLogEntry.objects.bulk_create([
        FoodLogEntry(client=client, date=day, logged_at=_same_time(r.logged_at, day, now) if r.other_time else now,
                     meal_name=r.meal_name, meal_id=r.meal_id, food=r.food,
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
            .select_related("plan", "custom_plan").order_by("-start_date").first())


def _shown(t, whole=False):
    """Totals as shown: kcal whole (a float like before unless [whole]), grams 1 decimal."""
    k = show_kcal(t["kcal"])
    return {"kcal": k if whole else float(k), "protein": show_g(t["protein"]), "carbs": show_g(t["carbs"]),
            "fat": show_g(t["fat"])}


def day_goal(client, plan, day, cache=None):
    """What the plan gives the client to eat on [day]: its meals' foods (default option, planned portions) added up,
    rounded as shown; None on a day without meals. Used as the day's target (Probid 2026-10-30).
    [cache] keeps one answer per (plan, weekday) across a range."""
    key = (plan.id, day.weekday())
    if cache is not None and key in cache:
        return cache[key]
    now = timezone.now()
    rows = []
    for meal in meals_on(plan, day.weekday()).prefetch_related("options__items__food__units", "options__items__unit"):
        opt = _option_for(meal, None)
        rows += [_entry_for_item(client, day, meal, it, None, now) for it in (opt.items.all() if opt else [])]
    out = _shown(nutrition_totals(rows), whole=True) if rows else None
    if cache is not None:
        cache[key] = out
    return out


def meal_kcal(client, meal, day):
    """One meal's planned kcal as shown (its default option's foods, planned portions)."""
    opt = _option_for(meal, None)
    now = timezone.now()
    rows = [_entry_for_item(client, day, meal, it, None, now) for it in (opt.items.all() if opt else [])]
    return show_kcal(nutrition_totals(rows)["kcal"]) if rows else 0


def totals(client, day):
    """What the client ate that day, unrounded (calc.nutrition_totals); round with show_kcal / show_g to show."""
    return nutrition_totals(FoodLogEntry.objects.filter(client=client, date=day))


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
        h = a.eff
        value = ml if h.unit.strip().lower() == "ml" else ml // 250
        HabitLog.objects.update_or_create(habit=h, client=client, date=day,
                                          defaults={"value": value, "done": bool(h.target) and value >= h.target})


def meal_opens_at(meal, day):
    """When a planned meal can be logged, skipped or changed: its time minus settings.MEAL_OPEN_BEFORE_MINUTES
    (Probid 2026-10-30: nothing before the meal's time)."""
    from django.conf import settings

    before = timedelta(minutes=getattr(settings, "MEAL_OPEN_BEFORE_MINUTES", 30))
    return timezone.make_aware(datetime.combine(day, meal.time)) - before


def check_meal_open(meal, day, now=None):
    """Refuses a change to a meal of today (or later) before it opens; earlier days are only synced late writes."""
    from rest_framework.exceptions import ValidationError

    today = timezone.localdate()
    if day < today:
        return
    at = meal_opens_at(meal, day)
    if day > today or (now or timezone.now()) < at:
        when = timezone.localtime(at)
        from apps.common.utils import dfmt

        raise ValidationError({"meal": [f"{meal.name} opens at {dfmt(when, '%-I:%M %p').lower()}"
                                        + ("" if day == today else f" on {dfmt(when, '%a %-d %b')}") + "."]})


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
    plan = mp.followed if mp else None
    states = {s.meal_id: s for s in MealDayState.objects.filter(client=client, date=day).select_related("option")
              .prefetch_related("more_photos")}
    entries = list(FoodLogEntry.objects.filter(client=client, date=day).order_by("logged_at"))
    meals = []
    planned_rows = []  # every planned food of the day at its planned portion (no swap): the day's target
    next_marked = False
    if plan:
        for meal in meals_on(plan, day.weekday()).prefetch_related("options__items__food__units",
                                                                      "options__items__unit"):
            st = states.get(meal.id)
            opt = _option_for(meal, st)
            pill = pill_for(meal, st, day, now)
            if pill == "next":
                if next_marked:
                    pill = "planned"
                next_marked = True
            items, exact, assigned = [], [], []
            apply_today = day == today  # swaps/portions only apply to today
            its = list(opt.items.all()) if opt else []
            if st is not None and not st.items and st.status:  # logged / skipped before foods had their own state
                st.items = {str(it.id): "eaten" if st.status == "logged" else "skipped" for it in its}
            for it in its:
                e = _entry_for_item(client, day, meal, it, st if apply_today else None, now)
                exact.append(e)
                # what the coach assigned: the planned portion, no swap (the "of" in "ate 446 of 259 kcal")
                a = e if not (apply_today and st and (st.portions or st.swaps)) else \
                    _entry_for_item(client, day, meal, it, None, now)
                assigned.append(a)
                planned_rows.append(a)
                items.append({"item": it.id, "food": e.food_id, "name": e.name, "quantity": float(e.quantity),
                              "unit": e.unit_name, "grams": float(e.grams), "kcal": show_kcal(e.kcal),
                              "protein": show_g(e.protein), "carbs": show_g(e.carbs), "fat": show_g(e.fat),
                              "swapped_from": e.swapped_from, "swaps": len(swaps.item_swaps(it)),
                              "planned_quantity": float(it.quantity),
                              # eaten | skipped | "" (not logged yet); edited: today's portion is not the planned one
                              "state": (st.items.get(str(it.id)) if st else None) or "",
                              "edited": bool(apply_today and st and str(it.id) in st.portions
                                             and float(st.portions[str(it.id)]) != float(it.quantity))})
            meals.append({
                "id": meal.id, "name": meal.name, "time": meal.time, "kcal_target": meal.kcal_target, "pill": pill,
                "option": opt.id if opt else None,
                "options": [{"id": o.id, "name": o.name, "is_default": o.is_default} for o in meal.options.all()],
                # meal total from the unrounded values, rounded once (calc.nutrition_totals)
                "items": items, **_shown(nutrition_totals(exact), whole=True), "_kcal": nutrition_totals(exact)["kcal"],
                # what she ate of it (the logged entries), next to the planned total above
                "assigned": _shown(nutrition_totals(assigned), whole=True),
                # before this a meal of today cannot be logged, skipped or changed (Probid 2026-10-30)
                "opens_at": meal_opens_at(meal, day),
                "eaten": _shown(nutrition_totals([e for e in entries if e.meal_id == meal.id
                                                  and e.source == FoodLogEntry.Source.PLAN]), whole=True),
                "logged_at": st.logged_at if st else None, "photo": url(st.photo) if st else None,
                "photos": ([url(st.photo)] if st and st.photo else [])
                          + ([url(p.image) for p in st.more_photos.all()] if st else []),
            })
    shown = _shown(totals(client, day))
    # The day's target is what the plan assigns her that day (the foods' total at the planned portions), not a
    # separate number (Probid 2026-10-30): eat every planned food and nothing is left. A day without meals keeps
    # the plan's figure.
    goal = _shown(nutrition_totals(planned_rows), whole=True) if planned_rows else None
    target = goal["kcal"] if goal else (plan.kcal_target if plan else None)
    planned_total = show_kcal(sum(m["_kcal"] for m in meals))
    still_ahead = show_kcal(sum(m["_kcal"] for m in meals if m["pill"] in ("next", "planned", "to_log")))
    for m in meals:
        del m["_kcal"]
    water = WaterLog.objects.filter(client=client, date=today).first()
    monday = day - timedelta(days=day.weekday())
    week = []
    per_day = [meals_on(plan, i).count() if plan else 0 for i in range(7)]
    logged = {}
    for d, n in (MealDayState.objects.filter(client=client, date__range=(monday, monday + timedelta(days=6)),
                                             status=MealDayState.Status.LOGGED)
                 .values_list("date").annotate(n=Count("id"))):
        logged[d] = n
    for i in range(7):
        d = monday + timedelta(days=i)
        n_meals = per_day[i]
        week.append({"date": d, **_shown(totals(client, d)), "meals_logged": logged.get(d, 0), "meals": n_meals,
                     "done": n_meals > 0 and logged.get(d, 0) >= n_meals})
    photos = {m["id"]: m["photo"] for m in meals if m.get("photo")}
    coach = getattr(getattr(client, "client_profile", None), "trainer", None)
    return {
        "date": day, "today": day == today, "can_log": day == today,
        "coach": coach.first_name if coach else "",
        "plan": {"id": plan.id, "name": plan.name, "kcal": target,
                 "protein": goal["protein"] if goal else plan.protein_g, "carbs": goal["carbs"] if goal else plan.carbs_g,
                 "fat": goal["fat"] if goal else plan.fat_g, "fibre": plan.fibre_g, "water_ml": plan.water_ml,
                 "version_note": mp.version_note, "allow_swaps": plan.allow_swaps,
                 "allow_search_any": plan.allow_search_any, "allow_switch_options": plan.allow_switch_options,
                 "allow_off_plan": plan.allow_off_plan} if plan else None,
        "ring": {"target": target, "eaten": shown["kcal"], "left": max((target or 0) - shown["kcal"], 0),
                 "planned": planned_total, "still_ahead": still_ahead},
        "macros": shown,
        "meals": meals,
        "log": [{"id": e.id, "time": e.logged_at, "meal_name": e.meal_name, "meal": e.meal_id, "name": e.name,
                 "quantity": float(e.quantity), "unit": e.unit_name, "kcal": show_kcal(e.kcal), "protein": show_g(e.protein),
                 "carbs": show_g(e.carbs), "fat": show_g(e.fat), "source": e.source, "food": e.food_id,
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
    prev = None
    if later:
        MealPlanAssignment.objects.filter(client=client, status="up_next").update(status="ended", end_date=today,
                                                                                  end_reason="replaced")
    else:
        prev = _end_current(client, today=today)
    a = MealPlanAssignment.objects.create(client=client, plan=plan, start_date=start_date if later else today,
                                          status="up_next" if later else "active", assigned_by=actor, replaced=prev)
    activity_log("assigned a meal plan", "plan", actor=actor, target=client, target_label=plan.name, client=client)
    if notify_client and not later and plan.status == MealPlan.Status.PUBLISHED:
        notify(client, "meal_plan_assigned", f"New meal plan: {plan.name}", "Open Food to see today's meals.",
               actor=actor, data={"route": "/food"})
    if actor is not None:
        from apps.notifications.staff import team_alert

        team_alert("plan_updated", client, f"{actor.first_name} gave {client.full_name} a meal plan", plan.name,
                   notify_event="plan_updated", actor=actor, data={"route": f"/clients/{client.id}"})
    return a


def end_client_plan(a, *, actor):
    a.status = "ended"
    a.end_date = timezone.localdate()
    a.end_reason = "ended"
    a.save(update_fields=["status", "end_date", "end_reason", "updated_at"])
    activity_log("ended a meal plan", "plan", actor=actor, target=a.client, target_label=a.plan.name, client=a.client)
    from apps.notifications.services import tell_clients

    tell_clients([a.client], "plan_ended", "Your meal plan has ended",
                 f"{a.plan.name} · {actor.first_name if actor else 'Your coach'} will set what is next",
                 actor=actor, route="/food")


# ---------------------------------------------------------------- one client's own copy (Plans → Edit for X)
def _clone_meals(meals, dst, weekday="keep", from_master=False):
    """Copy `meals` (options and items too) into plan `dst`. weekday "keep" keeps each meal's own weekday.
    [from_master]: making a client's copy: each item remembers its master item (`origin`, for "Was: …") and gets
    its own swaps, seeded from the food's library swaps when the master item has none of its own.
    Returns the (meal, option, item) id maps old → new."""
    mm, om, im = {}, {}, {}
    for m in meals.prefetch_related("options__items__food__swaps__default_unit", "options__items__unit"):
        nm = Meal.objects.create(plan=dst, name=m.name, time=m.time, kcal_target=m.kcal_target, order=m.order,
                                 weekday=m.weekday if weekday == "keep" else weekday)
        mm[m.id] = nm.id
        for o in m.options.all():
            no = MealOption.objects.create(meal=nm, name=o.name, is_default=o.is_default, order=o.order)
            om[o.id] = no.id
            for i in o.items.all():
                im[i.id] = MealItem.objects.create(
                    option=no, food_id=i.food_id, quantity=i.quantity, unit_id=i.unit_id, order=i.order,
                    alternatives=swaps.item_swaps(i) if from_master else i.alternatives,
                    origin_id=i.id if from_master else i.origin_id).id
    return mm, om, im


def _rekey(d, im):
    out = {}
    for k, v in (d or {}).items():
        try:
            out[str(im.get(int(k), k))] = v
        except (TypeError, ValueError):
            out[k] = v
    return out


def _move_days(client, maps, weekday=None):
    """Today's and later day states (logged / skipped, portions, swaps) and plan food logs of the old meals
    follow their copies, so a meal already logged today stays logged after the plan is edited."""
    mm, om, im = maps
    today = timezone.localdate()
    for st in MealDayState.objects.filter(client=client, date__gte=today, meal_id__in=list(mm)):
        if weekday is not None and st.date.weekday() != weekday:
            continue
        st.meal_id = mm[st.meal_id]
        st.option_id = om.get(st.option_id) if st.option_id else None
        st.portions, st.swaps = _rekey(st.portions, im), _rekey(st.swaps, im)
        st.save(update_fields=["meal", "option", "portions", "swaps", "updated_at"])
    for e in FoodLogEntry.objects.filter(client=client, date__gte=today, meal_id__in=list(mm)):
        if weekday is None or e.date.weekday() == weekday:
            e.meal_id = mm[e.meal_id]
            e.save(update_fields=["meal", "updated_at"])


def _carry_by_name(client, old_meals, plan):
    """Meals about to go away: today's and later day states (and their plan food logs) move to the meal of the
    same name that stays in `plan` (that day's own meals, else the every-day ones). No match: they go too."""
    today = timezone.localdate()
    old = {m.id: m.name.lower() for m in old_meals}
    rest = plan.meals.exclude(id__in=list(old))
    for st in MealDayState.objects.filter(client=client, date__gte=today, meal_id__in=list(old)):
        own = rest.filter(weekday=st.date.weekday())
        pool = own if own.exists() else rest.filter(weekday__isnull=True)
        new = {m.name.lower(): m.id for m in pool}.get(old[st.meal_id])
        if not new or MealDayState.objects.filter(client=client, date=st.date, meal_id=new).exists():
            continue
        was = st.meal_id
        st.meal_id, st.option_id, st.portions, st.swaps = new, None, {}, {}
        st.save(update_fields=["meal", "option", "portions", "swaps", "updated_at"])
        FoodLogEntry.objects.filter(client=client, date=st.date, meal_id=was).update(meal_id=new)


def _translate(meals_data, maps):
    """Ids the app sent for the old meals → the ids of their copies (unknown ids are left to be created)."""
    mm, om, im = maps
    out = []
    for md in meals_data:
        md = {**md, "id": mm.get(md.get("id"))}
        md["options"] = [{**od, "id": om.get(od.get("id")),
                          "items": [{**it, "id": im.get(it.get("id"))} for it in od.get("items", [])]}
                         for od in md.get("options", [])]
        out.append(md)
    return out


@transaction.atomic
def client_copy(a, *, actor):
    """The client's own copy of their meal plan, made on the first edit. Returns (copy, id maps or None)."""
    if a.custom_plan_id:
        return a.custom_plan, None
    src = a.plan
    copy = MealPlan.objects.create(
        name=src.name, diet=src.diet, kcal_target=src.kcal_target, protein_g=src.protein_g, carbs_g=src.carbs_g,
        fat_g=src.fat_g, fibre_g=src.fibre_g, water_ml=src.water_ml, status=src.status,
        published_at=src.published_at, allow_swaps=src.allow_swaps, allow_search_any=src.allow_search_any,
        allow_switch_options=src.allow_switch_options, allow_off_plan=src.allow_off_plan, is_master=False,
        master=src, created_by=actor)
    maps = _clone_meals(src.meals.all(), copy, from_master=True)
    a.custom_plan = copy
    a.save(update_fields=["custom_plan", "updated_at"])
    if a.status == "active":
        _move_days(a.client, maps)
    activity_log("edited a meal plan for one client", "plan", actor=actor, target=a.client, target_label=src.name,
                 client=a.client)
    return copy, maps


@transaction.atomic
def save_client_day(a, *, weekday, every_day, meals_data, actor):
    """Edit for X → Save: the meals of one weekday of the client's copy (`every_day`: the same meals on every
    day, which drops the other days' own meals). The master plan never changes."""
    plan, maps = client_copy(a, actor=actor)
    if maps:
        meals_data = _translate(meals_data, maps)
    own = plan.meals.filter(weekday=weekday)
    if every_day:
        if own.exists():
            _sync_set(plan, own, meals_data, weekday)
            gone = list(plan.meals.exclude(weekday=weekday))
            Meal.objects.filter(plan=plan, weekday=weekday).update(weekday=None)
        else:
            _sync_set(plan, plan.meals.filter(weekday__isnull=True), meals_data, None)
            gone = list(plan.meals.filter(weekday__isnull=False))
        if a.status == "active":
            _carry_by_name(a.client, gone, plan)
        Meal.objects.filter(id__in=[m.id for m in gone]).delete()
    else:
        if not own.exists():
            day_maps = _clone_meals(plan.meals.filter(weekday__isnull=True), plan, weekday)
            if a.status == "active":
                _move_days(a.client, day_maps, weekday)
            meals_data = _translate(meals_data, day_maps)
        _sync_set(plan, plan.meals.filter(weekday=weekday), meals_data, weekday)
    plan.save(update_fields=["updated_at"])
    return plan


@transaction.atomic
def reset_client_copy(a, *, actor=None):
    """Reset to master: the client follows the master plan again; the copy is kept hidden for the history."""
    copy = a.custom_plan
    a.custom_plan = None
    prev = a.version_note
    a.version_note = ""
    a.save(update_fields=["custom_plan", "version_note", "updated_at"])
    if copy is not None:
        if a.status == "active":
            _carry_by_name(a.client, list(copy.meals.all()), a.plan)
        copy.soft_delete()
        if actor:
            activity_log("reset a meal plan to master", "plan", actor=actor, target=a.client,
                         target_label=a.plan.name, client=a.client)
    return prev


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
               .select_related("plan", "custom_plan").order_by("-start_date"))

    def plan_on(d):
        return next((m.followed for m in mps if m.start_date <= d and (m.end_date is None or m.end_date >= d)),
                    None)

    logged = dict(MealDayState.objects.filter(client=client, date__range=(start, end), status=MealDayState.Status.LOGGED)
                  .values_list("date").annotate(n=Count("id")))
    sums = {r["date"]: r for r in FoodLogEntry.objects.filter(client=client, date__range=(start, end))
            .values("date").annotate(kcal=Sum("kcal"), protein=Sum("protein"), carbs=Sum("carbs"), fat=Sum("fat"))}
    n_meals = {}
    goals = {}
    rows = []
    for d in days:
        plan = plan_on(d)
        if plan is not None and (plan.id, d.weekday()) not in n_meals:
            n_meals[(plan.id, d.weekday())] = meals_on(plan, d.weekday()).count()
        meals = n_meals.get((plan.id, d.weekday()), 0) if plan else 0
        t = sums.get(d) or {}
        kcal = show_kcal(t.get("kcal"))  # was int(): cut 1799.6 down to 1799
        n = logged.get(d, 0)
        if not plan and not t:
            continue
        g = day_goal(client, plan, d, goals) if plan else None
        target = g["kcal"] if g else (plan.kcal_target if plan else None)
        if target and kcal > target * 1.05:
            st = "over"
        elif meals and n >= meals:
            st = "on_plan"
        elif n or kcal:
            st = "today" if d == today else ("partly" if meals else "logged")
        else:
            st = "today" if d == today else "missed"
        rows.append({"date": d, "kcal": kcal, "protein": show_g(t.get("protein")), "carbs": show_g(t.get("carbs")),
                     "fat": show_g(t.get("fat")), "meals_logged": n, "meals": meals, "kcal_target": target,
                     "status": st})
    cur = plan_on(min(end, today)) or (mps[0].followed if mps else None)
    out = page_of(rows, params)
    g = day_goal(client, cur, min(end, today), goals) if cur else None
    out["target"] = ({"kcal": g["kcal"], "protein": g["protein"], "carbs": g["carbs"], "fat": g["fat"]} if g else
                     {"kcal": cur.kcal_target, "protein": cur.protein_g, "carbs": cur.carbs_g, "fat": cur.fat_g}) \
        if cur else None
    return out
