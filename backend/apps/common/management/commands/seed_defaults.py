"""Built-in library every gym starts with. Safe to run again: existing rows are left alone."""
from django.core.management.base import BaseCommand
from django.db import transaction

from apps.common import seed_data as D


class Command(BaseCommand):
    help = "Create built-in exercises, foods, habits, supplement plans, forms, message templates and settings."

    @transaction.atomic
    def handle(self, *args, **opts):
        from apps.checkins.defaults import seed as seed_forms
        from apps.content.models import Category
        from apps.gym.models import GymSettings, RoleMatrix
        from apps.habits.models import Habit, SupplementItem, SupplementPlan
        from apps.notifications.defaults import seed as seed_notifications
        from apps.nutrition.models import Food, FoodUnit
        from apps.training.models import Exercise

        gym = GymSettings.load()
        # The About page's contact and coach card (ClientAbout board); only fills what is still empty.
        if not gym.phone:
            gym.phone = "+91 70874 03476"
        if gym.email in ("", "hello@trainwithvimal.com"):
            gym.email = "trainwithvimal@gmail.com"
        if not gym.coach_stats:
            gym.coach_stats = [["10+", "Years coaching"], ["300+", "Transformations"], ["17,000+", "Followers"]]
        gym.save()
        RoleMatrix.load()
        seed_notifications()
        seed_forms()

        made = 0
        for (name, muscle, primary, equip, level, log_type, sets, reps, rest, rpe, tempo, also) in D.EXERCISES:
            how, cues = D.HOW_TO.get(name, ([], []))
            have = Exercise.all_objects.filter(name=name, is_builtin=True).first()
            if have:
                if how and not have.how_to:  # steps added to the library later
                    have.how_to, have.form_cues = how, cues
                    have.save(update_fields=["how_to", "form_cues"])
                continue
            Exercise.objects.create(
                name=name, muscle_group=muscle, primary_muscle=primary, equipment=equip, level=level,
                log_type=log_type, default_sets=sets, default_reps=reps, default_rest_seconds=rest, default_rpe=rpe,
                default_tempo=tempo, also_works=[{"muscle": m, "level": lv} for m, lv in also], how_to=how,
                form_cues=cues, is_builtin=True)
            made += 1
        self.stdout.write(f"Exercises: {made} new")

        made = 0
        for (name, group, diet, kcal, p, c, f, fibre, units, default) in D.FOODS:
            if Food.all_objects.filter(name=name, source=Food.Source.BUILTIN).exists():
                continue
            food = Food.objects.create(name=name, group=group, diet=diet, kcal=kcal, protein=p, carbs=c, fat=f,
                                       fibre=fibre, source=Food.Source.BUILTIN, source_note="IFCT")
            for uname, grams in units:
                u = FoodUnit.objects.create(food=food, name=uname, grams=grams)
                if uname == default:
                    food.default_unit = u
            food.save(update_fields=["default_unit"])
            made += 1
        by_name = {f.name: f for f in Food.objects.filter(source=Food.Source.BUILTIN)}
        for name, swaps in D.SWAPS.items():
            if name in by_name:
                by_name[name].swaps.add(*[by_name[s] for s in swaps if s in by_name])
        self.stdout.write(f"Foods: {made} new")

        for (name, kind, target, unit, freq, days, tpw, icon, why) in D.HABITS:
            Habit.objects.get_or_create(name=name, defaults=dict(
                kind=kind, target=target, unit=unit, frequency=freq, days=days, times_per_week=tpw, icon=icon, why=why))
        for name, note, items in D.SUPPLEMENT_PLANS:
            plan, created = SupplementPlan.objects.get_or_create(name=name, defaults={"note": note})
            if created:
                SupplementItem.objects.bulk_create([
                    SupplementItem(plan=plan, name=n, dose=dose, how=how, timing=t, days=d, with_food=wf, order=i)
                    for i, (n, dose, how, t, d, wf) in enumerate(items)])
        for i, name in enumerate(D.CONTENT_CATEGORIES):
            Category.objects.get_or_create(name=name, defaults={"order": i})
        self.stdout.write(self.style.SUCCESS("Defaults ready."))
