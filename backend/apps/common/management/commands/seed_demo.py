"""Demo team and clients from the design boards, with a few weeks of history so every screen has data.
Run after seed_defaults. Safe to run again: people that already exist are skipped. Password: Demo@1234."""
import random
from datetime import timedelta
from decimal import Decimal

from django.core.management import call_command
from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone

PASSWORD = "Demo@1234"

# name, email, phone, speciality, max_clients, active
TRAINERS = [
    ("Aman Verma", "aman@trainwithvimal.com", "+919810000002", ["Strength", "Fat loss"], 30, True),
    ("Neha Joshi", "neha@trainwithvimal.com", "+919810000003", ["Yoga", "Mobility"], 25, True),
    ("Sahil Kapoor", "sahil@trainwithvimal.com", "+919810000004", ["Muscle gain"], 30, True),
    ("Karan Mehta", "karan@trainwithvimal.com", "+919810000005", ["Strength"], 20, True),
    ("Ritu Malhotra", "ritu@trainwithvimal.com", "+919810000006", ["Nutrition", "Fat loss"], 25, True),
    ("Meera Shah", "meera@trainwithvimal.com", "+919810000007", ["Women's fitness"], 20, True),
    ("Varun Kohli", "varun@trainwithvimal.com", "+919810000008", ["Conditioning"], 20, False),
]

# name, email, gender, goal, height, start kg, now kg, target kg, trainer email ("" = Vimal), package
CLIENTS = [
    ("Riya Sharma", "riya@example.com", "female", "fat_loss", 162, 72, 68.4, 62, "aman@trainwithvimal.com",
     "3 months · Online"),
    ("Rohan Kapoor", "rohan@example.com", "male", "muscle_gain", 178, 68, 70.2, 75, "aman@trainwithvimal.com",
     "6 months · Gym"),
    ("Ananya Iyer", "ananya@example.com", "female", "recomp", 165, 60, 59.1, 57, "neha@trainwithvimal.com",
     "3 months · Online"),
    ("Vikram Rao", "vikram@example.com", "male", "strength", 180, 82, 83, 85, "sahil@trainwithvimal.com",
     "6 months · Gym"),
    ("Dev Malhotra", "dev@example.com", "male", "fat_loss", 175, 94, 89.5, 80, "aman@trainwithvimal.com",
     "3 months · Gym"),
    ("Pooja Nair", "pooja@example.com", "female", "fat_loss", 158, 70, 67.8, 60, "ritu@trainwithvimal.com",
     "3 months · Online"),
    ("Arjun Rao", "arjun@example.com", "male", "muscle_gain", 172, 64, 66, 72, "", "12 months · Gym"),
    ("Ishaan Mehta", "ishaan@example.com", "male", "general", 176, 78, 77, 74, "karan@trainwithvimal.com",
     "1 month · Gym"),
    ("Priya Nair", "priya@example.com", "female", "recomp", 160, 58, 57.5, 56, "meera@trainwithvimal.com",
     "3 months · Online"),
    ("Kavya Menon", "kavya@example.com", "female", "fat_loss", 163, 76, 73.2, 64, "neha@trainwithvimal.com",
     "6 months · Online"),
    ("Sneha Kulkarni", "sneha@example.com", "female", "general", 166, 62, 62, 60, "", "3 months · Gym"),
    ("Nikhil Joshi", "nikhil@example.com", "male", "strength", 183, 88, 89, 90, "sahil@trainwithvimal.com",
     "6 months · Gym"),
]

UPPER = ["Barbell Bench Press", "Lat Pulldown", "Incline Dumbbell Press", "Seated Cable Row", "Push-up"]
LOWER = ["Barbell Back Squat", "Romanian Deadlift", "Leg Press", "Walking Lunge", "Dead Bug"]


class Command(BaseCommand):
    help = "Create the demo team, clients, a program, a meal plan and a few weeks of logs."

    def handle(self, *args, **opts):
        call_command("seed_defaults", verbosity=0)
        random.seed(42)
        with transaction.atomic():
            vimal = self.people()
            program, plan = self.plans(vimal)
            self.more_meal_plans(vimal)
            self.more_programs(vimal)
            self.history(program, plan)
            self.riya_home()
            self.riya_train()
            self.riya_checkins()
            self.riya_progress()
            self.riya_library()
            self.library_videos()
            self.exercise_media()
            self.library_link()
            self.aman_dashboard(program, plan)
            self.onboarding_answers()
            self.automations(vimal)
            self.settle_old_rows()
        self.stdout.write(self.style.SUCCESS(f"Demo ready. Log in with any demo email and {PASSWORD}"))
        self.stdout.write("Demo links (the reset link works for 15 minutes; run seed_demo again for new ones):")
        for line in self.demo_links():
            self.stdout.write("  " + line)

    def user(self, *, email, **fields):
        from apps.accounts.models import User

        u = User.objects.filter(email__iexact=email).first()
        if u:
            return u, False
        return User.objects.create_user(email=email, password=PASSWORD, email_verified_at=timezone.now(),
                                        **fields), True

    def people(self):
        from apps.accounts.models import AccountStatus, Role
        from apps.clients.models import ClientProfile
        from apps.trainers.models import AccessMode, TrainerProfile

        vimal, made = self.user(email="vimal@trainwithvimal.com", phone="+919810000001", full_name="Vimal Singh",
                                role=Role.ADMIN, status=AccountStatus.ACTIVE, city="Delhi", gender="male")
        if made:
            TrainerProfile.objects.create(user=vimal, is_owner=True, speciality=["Strength", "Fat loss"],
                                          max_clients=40, access_mode=AccessMode.ALL, experience_since=2012,
                                          languages=["Hindi", "English"])
        trainers = {"": vimal}
        today = timezone.localdate()
        for name, email, phone, spec, cap, active in TRAINERS:
            t, made = self.user(email=email, phone=phone, full_name=name, role=Role.TRAINER, city="Delhi",
                                status=AccountStatus.ACTIVE if active else AccountStatus.DEACTIVATED)
            if made:
                TrainerProfile.objects.create(user=t, speciality=spec, max_clients=cap, languages=["Hindi", "English"],
                                              experience_since=random.choice([2016, 2018, 2020]),
                                              joining_date=today - timedelta(days=random.randint(90, 900)))
            trainers[email] = t
        for i, (name, email, gender, goal, h, start, now, target, tr, package) in enumerate(CLIENTS):
            c, made = self.user(email=email, phone=f"+91982000{i:04d}", full_name=name, role=Role.CLIENT,
                                status=AccountStatus.ACTIVE, gender=gender, city="Delhi")
            answers = {
                "goal": {"goal": goal, "level": "intermediate"},
                "about": {"age": 24 + i, "height_cm": h, "weight_kg": start, "target_weight_kg": target, "place": "gym"},
                "schedule": {"days": ["mon", "tue", "thu", "fri"], "session_min": 45, "wake_time": "06:30"},
                "health": {"injuries": ["none"], "conditions": ["none"], "activity": "desk", "doctor_ok": True},
                "food": {"diet": "veg", "meals_per_day": 5, "avoid": [], "home_cooked": True},
            }
            if not made and not c.client_profile.onboarding:
                ClientProfile.objects.filter(user=c).update(onboarding=answers)
            if made:
                started = today - timedelta(weeks=6 + i % 4)
                ClientProfile.objects.create(
                    user=c, trainer=trainers[tr], goal=goal, height_cm=h, start_weight_kg=start,
                    current_weight_kg=now, target_weight_kg=target, start_date=started, package_name=package,
                    package_ends_on=started + timedelta(days=90 if package.startswith("3") else 180),
                    onboarding_done=["account", "basics", "goal_body", "health", "food"], ask_parq=False,
                    onboarding=answers)
        self.signups(vimal, trainers)
        return vimal

    def signups(self, vimal, trainers):
        """People who joined from an invite link and wait in Approvals, plus one added by a coach with setup to do."""
        from apps.accounts.models import User
        from apps.clients.models import SignupSource
        from apps.clients.services import create_client

        aman = trainers.get("aman@trainwithvimal.com") or next(iter(trainers.values()))
        rows = [
            ("Neha Gupta", "neha@example.com", True, {}),
            ("Karan Mehta", "karan@example.com", True, {"goal": {"goal": "muscle_gain", "level": "beginner"}}),
            ("Isha Rao", "isha@example.com", False, {}),
        ]
        for name, email, pending, answers in rows:
            if User.objects.filter(email__iexact=email).exists():
                continue
            u, cp = create_client(actor=vimal, full_name=name, email=email, trainer=aman, send_to_approvals=pending,
                                  send_login_link=False, password=PASSWORD,
                                  source=SignupSource.WEB if pending else SignupSource.ADDED)
            User.objects.filter(pk=u.pk).update(email_verified_at=timezone.now())
            if answers:
                cp.onboarding = answers
                cp.save(update_fields=["onboarding"])

        # Joined from an invite link but has not confirmed the email yet → the Verify email page.
        if not User.objects.filter(email__iexact="tara@example.com").exists():
            create_client(actor=None, full_name="Tara Singh", email="tara@example.com", phone="+919820011223",
                          trainer=aman, send_to_approvals=True, send_login_link=False, password=PASSWORD,
                          source=SignupSource.WEB)
        # Added by a coach, no password yet → the login link page.
        if not User.objects.filter(email__iexact="sana@example.com").exists():
            create_client(actor=aman, full_name="Sana Khan", email="sana@example.com", phone="+919845022118",
                          trainer=aman, send_to_approvals=False, send_login_link=False, password=None,
                          source=SignupSource.ADDED)
        # The invite link from the Join board.
        from apps.clients.models import InviteLink

        InviteLink.objects.get_or_create(code="AMAN-4821", defaults={
            "trainer": aman, "label": "WhatsApp · demo", "needs_approval": True,
            "expires_at": timezone.now() + timedelta(days=30), "created_by": vimal})

    def demo_links(self):
        """Fresh one-time links for trying the Login link, Verify email and Reset password pages."""
        from django.conf import settings

        from apps.accounts.models import OneTimeToken, User
        from apps.accounts.tokens import issue_one_time_token

        base = settings.FRONTEND_URL.rstrip("/")
        out = [f"Invite link:     {base}/join/AMAN-4821"]
        for email, purpose, path in [("sana@example.com", OneTimeToken.Purpose.LOGIN_LINK, "start"),
                                     ("tara@example.com", OneTimeToken.Purpose.EMAIL_VERIFY, "verify-email"),
                                     ("riya@example.com", OneTimeToken.Purpose.PASSWORD_RESET, "reset-password")]:
            u = User.objects.filter(email__iexact=email).first()
            if u:
                out.append(f"{path + ':':16} {base}/{path}?token={issue_one_time_token(u, purpose, email=u.email)}")
        return out

    def plans(self, vimal):
        from apps.accounts.models import User
        from apps.nutrition.models import Food, MealItem, MealPlan, MealPlanAssignment
        from apps.nutrition.services import new_plan
        from apps.training.models import AssignmentStatus, Exercise, Program, ProgramAssignment, ProgramExercise
        from apps.training.services import new_program

        program = Program.objects.filter(name="Fat loss · 8 weeks").first()
        if program is None:
            program = new_program(name="Fat loss · 8 weeks", weeks=8, days_per_week=4, goal_line="Fat loss · gym",
                                  level="intermediate", actor=vimal)
            ex = {e.name: e for e in Exercise.objects.filter(is_builtin=True)}
            for week in program.program_weeks.all():
                for day in week.days.filter(is_rest=False):
                    names = UPPER if day.weekday % 2 == 0 else LOWER
                    day.name = "Upper A" if day.weekday % 2 == 0 else "Lower A"
                    day.save(update_fields=["name"])
                    for order, n in enumerate(x for x in names if x in ex):
                        e = ex[n]
                        ProgramExercise.objects.create(day=day, exercise=e, order=order, sets=e.default_sets,
                                                       reps=e.default_reps, rest_seconds=e.default_rest_seconds,
                                                       rpe=e.default_rpe, tempo=e.default_tempo)
                week.days.filter(is_rest=True).update(rest_note="8k steps and 10 minutes of mobility")

        if program.level == "any":  # older seeds had no level
            Program.objects.filter(id=program.id).update(level="intermediate")
            program.level = "intermediate"

        plan = MealPlan.objects.filter(name="Veg fat loss · 1,800").first()
        if plan is None:
            plan = new_plan(name="Veg fat loss · 1,800", diet="veg", kcal_target=1800, actor=vimal)
            foods = {f.name: f for f in Food.objects.filter(source=Food.Source.BUILTIN).prefetch_related("units")}
            menu = {"Breakfast": [("Oats", 1), ("Whey protein", 1), ("Banana", 1)],
                    "Lunch": [("Whole wheat roti", 2), ("Dal tadka", 1), ("Mixed veg sabzi", 1), ("Curd", 1)],
                    "Snack": [("Roasted chana", 1), ("Apple", 1)],
                    "Dinner": [("Paneer bhurji", 1), ("Whole wheat roti", 2), ("Cucumber salad", 1)]}
            for meal in plan.meals.all():
                opt = meal.options.first()
                for order, (n, qty) in enumerate(menu.get(meal.name, [])):
                    f = foods[n]
                    MealItem.objects.create(option=opt, food=f, quantity=qty, unit=f.default_unit, order=order)
            plan.status, plan.published_at = MealPlan.Status.PUBLISHED, timezone.now()
            plan.save(update_fields=["status", "published_at"])

        for c in User.objects.filter(role="client", client_profile__start_date__isnull=False).select_related("client_profile"):
            cp = c.client_profile
            if not ProgramAssignment.objects.filter(client=c).exists():
                ProgramAssignment.objects.create(client=c, program=program, start_date=cp.start_date,
                                                 status=AssignmentStatus.ACTIVE, assigned_by=cp.trainer)
            if not MealPlanAssignment.objects.filter(client=c).exists():
                MealPlanAssignment.objects.create(client=c, plan=plan, start_date=cp.start_date, assigned_by=cp.trainer)
        return program, plan

    # Programs page (board Programs): more master plans so the cards, tabs and Archived have something to show.
    # [name, goal line, weeks, level, archived, days: (weekday, name, exercises)]; other weekdays are rest days.
    MORE_PROGRAMS = [
        ("Hypertrophy · Push / Pull / Legs", "Muscle gain · 5 days", 8, "intermediate", False, [
            (0, "Push", ["Barbell Bench Press", "Incline Dumbbell Press", "Overhead Press", "Triceps Pushdown"]),
            (1, "Pull", ["Pull-up", "Bent-over Barbell Row", "Face Pull", "Barbell Curl"]),
            (2, "Legs", ["Back Squat", "Romanian Deadlift", "Leg Press", "Walking Lunge"]),
            (4, "Upper", ["Barbell Bench Press", "Seated Cable Row", "Dumbbell Lateral Raise", "Hammer Curl"]),
            (5, "Lower", ["Hip Thrust", "Goblet Squat", "Walking Lunge", "Plank"])]),
        ("Beginner Full Body", "General fitness · 3 days", 4, "beginner", False, [
            (0, "Full body A", ["Goblet Squat", "Push-up", "Lat Pulldown", "Plank"]),
            (2, "Full body B", ["Romanian Deadlift", "Incline Dumbbell Press", "Seated Cable Row", "Dead Bug"]),
            (4, "Full body C", ["Leg Press", "Overhead Press", "Single-arm Dumbbell Row", "Hanging Knee Raise"])]),
        ("Yoga Strength", "Mobility and strength · 3 days", 6, "any", False, [
            (0, "Strength and balance", ["Goblet Squat", "Push-up", "Plank"]),
            (2, "Hips and back", ["Hip Thrust", "Dead Bug", "Face Pull"]),
            (5, "Easy cardio", ["Treadmill Walk"])]),
        ("Strength Base", "Strength · 4 days", 10, "advanced", False, [
            (0, "Squat day", ["Back Squat", "Box Squat", "Plank"]),
            (1, "Bench day", ["Barbell Bench Press", "Bench Dips", "Triceps Pushdown"]),
            (3, "Pull day", ["Bent-over Barbell Row", "Pull-up", "Barbell Curl"]),
            (4, "Hinge day", ["Romanian Deadlift", "Kettlebell Swing", "Hanging Knee Raise"])]),
        ("Shoulder-safe Upper Body", "Rehab · 2 days", 4, "beginner", True, [
            (1, "Upper A", ["Face Pull", "Incline Dumbbell Press", "Seated Cable Row"]),
            (4, "Upper B", ["Dumbbell Lateral Raise", "Lat Pulldown", "Push-up"])]),
    ]

    def more_programs(self, vimal):
        from apps.training.models import Exercise, Program, ProgramExercise
        from apps.training.services import new_program

        ex = {e.name: e for e in Exercise.objects.filter(is_builtin=True)}
        for name, goal, weeks, level, archived, days in self.MORE_PROGRAMS:
            if Program.all_objects.filter(name=name, is_master=True).exists():
                continue
            p = new_program(name=name, weeks=weeks, days_per_week=len(days), goal_line=goal, level=level, actor=vimal)
            plan = {wd: (n, xs) for wd, n, xs in days}
            for week in p.program_weeks.all():
                for day in week.days.all():
                    d = plan.get(day.weekday)
                    day.is_rest, day.name = d is None, d[0] if d else "Rest"
                    day.rest_note = "" if d else "8k steps and 10 minutes of mobility"
                    day.save(update_fields=["is_rest", "name", "rest_note"])
                    for order, n in enumerate(x for x in (d[1] if d else []) if x in ex):
                        e = ex[n]
                        ProgramExercise.objects.create(day=day, exercise=e, order=order, sets=e.default_sets,
                                                       reps=e.default_reps, rest_seconds=e.default_rest_seconds,
                                                       rpe=e.default_rpe, tempo=e.default_tempo)
            if archived:
                Program.objects.filter(id=p.id).update(archived_at=timezone.now())

    # Nutrition & foods (board Nutrition): more master meal plans so the cards, diet chips and Draft have content.
    # [name, diet, kcal, published, {meal: [option name, [(food, quantity)]]...}]
    MORE_MEAL_PLANS = [
        ("Cut · Eggetarian", "egg", 2150, True, {
            "Breakfast": [("Veg", [("Oats", 1), ("Whey protein", 1), ("Banana", 1), ("Peanut butter", 1)]),
                          ("Eggs", [("Boiled egg", 3), ("Multigrain bread", 2), ("Apple", 1)])],
            "Lunch": [("Veg", [("Paneer", 1), ("Whole wheat roti", 2), ("Moong dal (cooked)", 1)]),
                      ("Non-veg", [("Chicken breast (cooked)", 1), ("Brown rice (cooked)", 1)])],
            "Snack": [("Quick", [("Greek yogurt", 1), ("Roasted chana", 1)]), ("Shake", [("Whey protein", 1), ("Milk (toned)", 1)])],
            "Dinner": [("Eggetarian", [("Egg white", 6), ("Boiled egg", 1), ("Brown rice (cooked)", 1), ("Mixed veg sabzi", 1)]),
                       ("Veg", [("Tofu (firm)", 1), ("Whole wheat roti", 2), ("Spinach (cooked)", 1)])]}),
        ("Lean gain · Non-veg", "nonveg", 2800, True, {
            "Breakfast": [("Eggs", [("Boiled egg", 4), ("Multigrain bread", 3), ("Banana", 1)])],
            "Lunch": [("Chicken", [("Chicken breast (cooked)", 1), ("White rice (cooked)", 2), ("Dal tadka", 1)])],
            "Snack": [("Pre-workout", [("Banana", 1), ("Peanut butter", 1), ("Whey protein", 1)])],
            "Dinner": [("Fish", [("Fish curry", 1), ("White rice (cooked)", 1), ("Cucumber salad", 1)]),
                       ("Chicken", [("Chicken breast (cooked)", 1), ("Whole wheat roti", 3)])]}),
        ("Fat loss · Veg", "veg", 1700, False, {
            "Breakfast": [("Veg", [("Poha", 1), ("Curd", 1)]), ("Quick", [("Oats", 1), ("Milk (toned)", 1)])],
            "Lunch": [("Veg", [("Whole wheat roti", 2), ("Rajma (cooked)", 1), ("Cucumber salad", 1)])],
            "Snack": [("Light", [("Makhana", 1), ("Papaya", 1)])],
            "Dinner": [("Veg", [("Paneer bhurji", 1), ("Whole wheat roti", 1), ("Mixed veg sabzi", 1)])]}),
        ("Maintenance · Vegan", "vegan", 2200, False, {
            "Breakfast": [("Vegan", [("Idli", 3), ("Sambar", 1)])],
            "Lunch": [("Vegan", [("Brown rice (cooked)", 1), ("Chana (cooked)", 1), ("Spinach (cooked)", 1)])],
            "Snack": [("Vegan", [("Sprouts chaat", 1), ("Almonds", 1)])],
            "Dinner": [("Vegan", [("Tofu (firm)", 1), ("Whole wheat roti", 2), ("Mixed veg sabzi", 1)])]}),
    ]

    def more_meal_plans(self, vimal):
        from apps.nutrition.models import Food, MealItem, MealOption, MealPlan
        from apps.nutrition.services import new_plan

        foods = {f.name: f for f in Food.objects.filter(owner_client__isnull=True).select_related("default_unit")}
        for name, diet, kcal, published, meals in self.MORE_MEAL_PLANS:
            if MealPlan.all_objects.filter(name=name, is_master=True).exists():
                continue
            p = new_plan(name=name, diet=diet, kcal_target=kcal, actor=vimal)
            for meal in p.meals.all():
                meal.options.all().delete()
                for o_order, (oname, items) in enumerate(meals.get(meal.name, [])):
                    opt = MealOption.objects.create(meal=meal, name=oname, is_default=o_order == 0, order=o_order)
                    for order, (n, qty) in enumerate(i for i in items if i[0] in foods):
                        f = foods[n]
                        MealItem.objects.create(option=opt, food=f, quantity=qty, unit=f.default_unit, order=order)
            if published:
                p.status, p.published_at = MealPlan.Status.PUBLISHED, timezone.now()
                p.save(update_fields=["status", "published_at"])

    def history(self, program, plan):
        """Weights, finished workouts, eaten meals, water and habits for the last 3 weeks."""
        from apps.accounts.models import User
        from apps.checkins.models import WeightLog
        from apps.clients.metrics import refresh_client_stats
        from apps.habits.models import Habit, HabitAssignment, HabitLog
        from apps.nutrition.models import WaterLog
        from apps.nutrition.services import mark_eaten
        from apps.training.models import ProgramAssignment

        today = timezone.localdate()
        habits = list(Habit.objects.filter(name__in=["Drink 3 L water", "8,000 steps", "Sleep by 11 pm"]))
        for c in User.objects.filter(role="client", client_profile__start_date__isnull=False).select_related("client_profile"):
            if WeightLog.objects.filter(client=c).exists():
                continue
            cp = c.client_profile
            steady = random.random() > 0.25  # a few clients fall behind, so "Needs attention" has rows
            weeks = max(1, (today - cp.start_date).days // 7)
            for w in range(weeks + 1):
                d = cp.start_date + timedelta(weeks=w)
                kg = cp.start_weight_kg + (cp.current_weight_kg - cp.start_weight_kg) * Decimal(w) / Decimal(weeks)
                WeightLog.objects.get_or_create(client=c, date=min(d, today), defaults={"weight_kg": round(kg, 1)})
            for h in habits:
                HabitAssignment.objects.get_or_create(habit=h, client=c, defaults={"start_date": cp.start_date})
            assignment = ProgramAssignment.objects.filter(client=c).first()
            for back in range(21, 0, -1):
                day = today - timedelta(days=back)
                if not steady and back < 9 or day < cp.start_date:  # nothing logged before they joined
                    continue
                WaterLog.objects.update_or_create(client=c, date=day, defaults={"ml": random.choice([2000, 2500, 3000])})
                for h in habits:
                    HabitLog.objects.update_or_create(habit=h, client=c, date=day, defaults={
                        "done": random.random() > 0.3, "value": (h.target or 1) if random.random() > 0.3 else 0})
                for meal in plan.meals.all():
                    if random.random() > 0.2:
                        mark_eaten(c, meal, day)
                if day.weekday() < program.days_per_week and assignment:
                    self.workout(c, assignment, program, day)
            refresh_client_stats(cp)

    def riya_train(self):
        """Train tab: the coach's note on each workout day and on a few exercises (guide sheet)."""
        from apps.training.models import Program, ProgramDay, ProgramExercise

        program = Program.objects.filter(name="Fat loss · 8 weeks", is_master=True).first()
        if program is None:
            return
        days = ProgramDay.objects.filter(week__program=program, is_rest=False)
        days.filter(name="Lower A", rest_note="").update(
            rest_note="Keep the deadlifts slow on the way down. If the knee hurts on the lunges, make the steps shorter.")
        days.filter(name="Upper A", rest_note="").update(
            rest_note="Two warm-up sets on the bench first. Stop each set with one or two reps left in the tank.")
        notes = {"Romanian Deadlift": "Stay on the same weight until all 3 sets of 10 feel clean, then add 2.5 kg.",
                 "Walking Lunge": "Short steps are fine. Hold the dumbbells by your sides, not on the shoulders.",
                 "Dead Bug": "Lower back flat on the mat the whole time. If it lifts, do not lower the leg so far.",
                 "Barbell Bench Press": "Two warm-up sets first. Next step 47.5 kg."}
        for name, note in notes.items():
            ProgramExercise.objects.filter(day__week__program=program, exercise__name=name, note="").update(note=note)

    def riya_home(self):
        """Fills every card of Riya's Home board: supplements, today's session, a coach reply, the bell,
        and a habit that starts next Monday."""
        from apps.accounts.models import User
        from apps.checkins.models import Form, Submission
        from apps.habits.models import Habit, HabitAssignment, SupplementAssignment, SupplementPlan
        from apps.notifications.models import Notification
        from apps.scheduling.models import Session

        riya = User.objects.filter(email__iexact="riya@example.com").select_related("client_profile").first()
        if riya is None or riya.client_profile.trainer is None:
            return
        aman, today, now = riya.client_profile.trainer, timezone.localdate(), timezone.now()
        sp = SupplementPlan.objects.filter(name="Fat loss support").first()
        if sp and not SupplementAssignment.objects.filter(client=riya).exists():
            SupplementAssignment.objects.create(plan=sp, client=riya, start_date=today - timedelta(days=14),
                                                assigned_by=aman)
        if not Session.objects.filter(client=riya, start__gte=now, status=Session.Status.BOOKED).exists():
            start = timezone.make_aware(timezone.datetime.combine(today, timezone.datetime.min.time())) \
                + timedelta(hours=18, minutes=30)
            if start < now:
                start += timedelta(days=1)
            Session.objects.create(client=riya, trainer=aman, title="Lower A", start=start,
                                   end=start + timedelta(minutes=60), place="Gym floor", booked_by=aman)
        # The board's habits: steps, water (from the water card) and sleep hours.
        sleep = Habit.objects.filter(name="Sleep 7 hours").first()
        if sleep:
            HabitAssignment.objects.get_or_create(habit=sleep, client=riya,
                                                  defaults={"start_date": riya.client_profile.start_date or today,
                                                            "assigned_by": aman})
            HabitAssignment.objects.filter(client=riya, habit__name="Sleep by 11 pm").update(active=False)
        # Halfway through today, like the board: 1.5 L water, 6,240 steps, 7 h 20 min sleep, 2 of 3 supplements.
        from apps.habits.models import HabitLog, SupplementLog
        from apps.nutrition.models import WaterLog
        from apps.nutrition.services import add_water

        if not WaterLog.objects.filter(client=riya, date=today).exists():
            add_water(riya, 1500, today)
        for name, value, target in [("8,000 steps", 6240, 8000), ("Sleep 7 hours", 440, 420)]:
            h = Habit.objects.filter(name=name).first()
            if h:
                HabitLog.objects.get_or_create(habit=h, client=riya, date=today,
                                               defaults={"value": value, "done": value >= target})
        if sp and not SupplementLog.objects.filter(client=riya, date=today).exists():
            for it in sp.items.filter(name__in=["Whey protein", "Vitamin D3"]):
                SupplementLog.objects.create(item=it, client=riya, date=today)
        # Stock at home, like the board's supplement sheet (Habits page): 12 scoops, 20 and 30 tablets.
        from apps.habits.models import SupplementStock

        for it in (sp.items.all() if sp else []):
            q, u = {"Whey protein": (12, "scoops"), "Vitamin D3": (20, "tablets")}.get(it.name, (30, "tablets"))
            SupplementStock.objects.get_or_create(item=it, client=riya, defaults={"quantity": q, "unit": u})
        sugar = Habit.objects.filter(name="No sugary drinks").first()
        if sugar:
            monday = today + timedelta(days=7 - today.weekday())
            HabitAssignment.objects.get_or_create(habit=sugar, client=riya,
                                                  defaults={"start_date": monday, "assigned_by": aman})
        weekly = Form.objects.filter(type="weekly", status="published").first()
        if weekly and not Submission.objects.filter(client=riya).exclude(reply="").exists():
            Submission.objects.create(
                form=weekly, form_type="weekly", client=riya, date=today - timedelta(days=6),
                reviewed_at=now - timedelta(hours=2), reviewed_by=aman,
                reply="Great week, Riya. Your squat looks much better. Keep the protein up on rest days too.")
        if not Notification.objects.filter(recipient=riya).exists():
            for ago, event, title, body, read in [
                (2, "checkin_reviewed", "Aman replied to your check-in", "Great week, Riya. Your squat looks better.",
                 False),
                (5, "session_booked", "Session booked", "Today · 6:30 pm · Gym floor", False),
                (26, "plan_updated", "Your meal plan was updated", "Veg fat loss · 1,800", True),
            ]:
                n = Notification.objects.create(recipient=riya, actor=aman, event=event, title=title, body=body,
                                                read_at=now if read else None)
                Notification.objects.filter(pk=n.pk).update(created_at=now - timedelta(hours=ago))

    def riya_progress(self):
        """Progress board: measurements every 2 weeks since day 1 and four photo sets (start, weeks 2, 4, 6; the
        week 2 set has no Back photo). The photos are drawn placeholders, so the timeline and Compare have data."""
        from apps.accounts.models import User
        from apps.checkins.models import Measurement, PhotoSet, ProgressPhoto, WeightLog

        riya = User.objects.get(email="riya@example.com")
        if Measurement.objects.filter(client=riya).exists():
            return
        today, start = timezone.localdate(), riya.client_profile.start_date
        # waist, hips, chest, arm, body fat — a little lower each time
        base = [(84, 102, 93, 29.5, 31), (82.5, 101, 92, 29, 30), (81, 100, 91.5, 28.5, 29), (79.5, 99, 91, 28.5, 28)]
        for i, (wa, hi, ch, ar, bf) in enumerate(base):
            d = start + timedelta(days=14 * i)
            if d > today:
                break
            Measurement.objects.create(client=riya, date=d, values={"waist": wa, "hips": hi, "chest": ch,
                                                                    "bicep_l": ar, "bicep_r": ar + .5, "body_fat": bf})
        tints = [((219, 230, 252), (88, 120, 220)), ((220, 240, 228), (70, 150, 100)),
                 ((236, 228, 250), (140, 110, 210)), ((252, 236, 220), (210, 140, 70))]
        last_sunday = today - timedelta(days=today.weekday() + 1)
        sets = [(start, "Start photos", ["front", "side", "back"])]
        for wk, poses in ((2, ["front", "side"]), (4, ["front", "side", "back"]), (6, ["front", "side", "back"])):
            d = start + timedelta(days=7 * wk - 1)
            d -= timedelta(days=(d.weekday() + 1) % 7)  # that week's Sunday check-in
            if d <= last_sunday:
                sets.append((d, f"Week {wk} check-in", poses))
        for i, (d, label, poses) in enumerate(sets):
            w = WeightLog.objects.filter(client=riya, date__lte=d).order_by("-date").first()
            ps = PhotoSet.objects.create(client=riya, date=d, label=label, weight_kg=w.weight_kg if w else None)
            for pose in poses:
                ProgressPhoto.objects.create(photo_set=ps, pose=pose,
                                             image=_figure(f"{pose}.jpg", *tints[i % len(tints)], pose))

    def exercise_media(self):
        """Exercise guide media, one of each kind: Leg Press an uploaded video, Romanian Deadlift a picture, Walking
        Lunge a YouTube video. The uploads are not shared with clients, so they show in the guide, not the Library.
        Running it again fills a video that has no file yet (older demo data made without ffmpeg)."""
        from apps.accounts.models import User
        from apps.content.models import ContentItem
        from apps.training.models import Exercise

        vimal = User.objects.get(email="vimal@trainwithvimal.com")
        for name, kind, title, sec in [("Leg Press", "video", "Leg press: how to", 42),
                                       ("Romanian Deadlift", "image", "Romanian deadlift: the hinge", 0)]:
            ex = Exercise.objects.filter(name=name, is_builtin=True).first()
            if ex is None:
                continue
            item = ex.video or ContentItem.objects.create(kind=kind, title=title, created_by=vimal,
                                                          duration_seconds=sec or None,
                                                          description=f"How to do the {name.lower()} with good form.")
            if not item.file:
                f = _video("leg-press", sec) if kind == "video" else _hinge_card()
                if f is not None:
                    item.file = f
                    item.save()
            if ex.video_id != item.id:
                ex.video = item
                ex.save(update_fields=["video"])
        lunge = Exercise.objects.filter(name="Walking Lunge", is_builtin=True).first()
        if lunge is not None and not lunge.youtube_url:
            lunge.video = None
            lunge.youtube_url = "https://www.youtube.com/watch?v=YYWhkctnP2o"
            lunge.save(update_fields=["video", "youtube_url"])

    def library_videos(self):
        """Older demo data made without ffmpeg has Library videos with no file: attach the shipped ones."""
        from apps.content.models import ContentItem

        for title, slug, sec in [("Box squat: how to", "box", 185), ("Upper A walkthrough", "upa", 380)]:
            item = ContentItem.objects.filter(title=title, kind="video").first()
            if item is not None and not item.file:
                f = _video(slug, sec)
                if f is not None:
                    item.file = f
                    item.save()

    def library_link(self):
        """A reference link in Riya's Library (kind=link): Aman shares a web page with a note."""
        from apps.accounts.models import User
        from apps.content.models import ContentItem, ContentShare

        title = "Protein sources for vegetarians"
        riya = User.objects.filter(email="riya@example.com").first()
        aman = User.objects.filter(email="aman@trainwithvimal.com").first()
        if riya is None or aman is None or ContentItem.objects.filter(title=title).exists():
            return
        it = ContentItem.objects.create(
            kind="link", title=title, created_by=aman,
            link_url="https://www.healthline.com/nutrition/protein-for-vegans-vegetarians",
            description="A good list of veg protein foods with grams of protein per serving.")
        sh = ContentShare.objects.create(item=it, client=riya, shared_by=aman, source="coach",
                                         note="Read the dal, paneer and soya parts. Pick two to add to your lunch.")
        ContentShare.objects.filter(id=sh.id).update(created_at=timezone.now() - timedelta(days=3))

    def riya_library(self):
        """Library board: eight items (2 videos, 3 PDFs, 1 image, 2 articles) shared four ways: by Aman with a
        note, with the program, with the meal plan, and for all clients. Videos, PDFs and the image are small real
        files made here (videos need ffmpeg; without it they have no file and the app says so)."""
        from apps.accounts.models import User
        from apps.content.models import ContentItem, ContentShare, ContentView

        riya = User.objects.get(email="riya@example.com")
        if ContentItem.objects.filter(title="Box squat: how to").exists():
            _refresh_shipped_pdfs(ContentItem)
            ContentItem.objects.filter(title="How to warm up for leg day", body__startswith="Start with 5").update(
                body=LEG_WARMUP)
            _file_content()
            return
        aman = User.objects.get(email="aman@trainwithvimal.com")
        vimal = User.objects.get(email="vimal@trainwithvimal.com")
        sahil = User.objects.get(email="sahil@trainwithvimal.com")
        today = timezone.localdate()
        program, plan = "Fat loss · 8 weeks", "your meal plan"
        snacks = [("Roasted chana · 45 g", "165 kcal"), ("Sprouts chaat · 1 plate", "180 kcal"),
                  ("Makhana · 30 g", "105 kcal"), ("Greek yogurt · 150 g", "110 kcal"),
                  ("Apple + 10 almonds", "165 kcal"), ("Moong chilla · 1", "150 kcal"),
                  ("Paneer tikka · 60 g", "170 kcal"), ("Chaas + chana · 20 g", "140 kcal"),
                  ("Fruit chaat · 1 bowl", "120 kcal"), ("Corn chaat · 1 bowl", "150 kcal")]
        items = [
            dict(id="box", kind="video", title="Box squat: how to", by=aman, dur=185,
                 description="How to set the box height, sit back with control and stand up without bouncing. "
                             "Good for squatting with a sore knee.",
                 chapters=[[0, "Setting the box height"], [48, "Sitting back"], [115, "Driving up"],
                           [150, "Common mistakes"]],
                 share=("coach", "", 18, "Use box squats on Saturday until the knee feels fine. Sit back to the "
                                         "box, pause for a second, then drive up."), seen=True),
            dict(id="eat", kind="pdf", title="Eating out on a fat loss plan", by=vimal,
                 description="Pick grilled over fried, ask for dressing on the side, and start with a protein. "
                             "Here are 12 orders that fit your plan.",
                 outline=[["Eating out is fine", "One meal out does not undo a week. Plan it, enjoy it, log it."],
                          ["Rules of thumb", "Protein first, grilled over fried, sauces on the side."],
                          ["Reading an Indian menu", "Tandoori, tikka and dal are safe picks. Watch for makhani "
                                                     "and malai."],
                          ["12 orders that fit your plan", "Paneer tikka, dal tadka with 1 roti, grilled fish "
                                                           "with salad and more."],
                          ["Drinks and desserts", "Chaas or fresh lime soda without sugar. Share one dessert."],
                          ["Back to plan", "Log it honestly and go back to your plan at the next meal."]],
                 share=("coach", "", 15, "Read this before Saturday’s family dinner. Page 4 has orders that fit "
                                         "your plan."), seen=False),
            dict(id="upa", kind="video", title="Upper A walkthrough", by=vimal, dur=380,
                 description="Every exercise of Upper A, with the setup and the one cue that matters most for "
                             "each.",
                 chapters=[[0, "Warm-up sets"], [100, "Bench press"], [210, "Rows and pulldowns"],
                           [310, "Arms finisher"]],
                 share=("program", program, 40, ""), seen=True),
            dict(id="leg", kind="article", title="How to warm up for leg day", by=vimal, mins=4,
                 description="Ten minutes that make your squats feel better and keep the knees happy.",
                 body=LEG_WARMUP,
                 share=("program", program, 40, ""), seen=True, done=True),
            dict(id="macro", kind="pdf", title="Macro cheat sheet", by=aman,
                 description="Protein: 1.6 to 2 g per kg of body weight. One palm of paneer, chicken, fish or "
                             "tofu is about 25 g.",
                 outline=[["Your daily targets", "1,800 kcal · 112 g protein · 200 g carbs · 60 g fat."],
                          ["Protein in common foods", "Paneer 100 g: 18 g · Tofu 100 g: 15 g · Greek yogurt "
                                                      "150 g: 15 g."]],
                 share=("coach", "", 66, "Keep this handy for grocery runs. Your targets: 112 g protein, 200 g "
                                         "carbs, 60 g fat."), seen=True, saved=True),
            dict(id="snacks", kind="image", title="10 veg snacks under 200 kcal", by=sahil,
                 description="Quick vegetarian snacks with their calories. All of them fit your evening snack.",
                 tiles=snacks,
                 share=("meal_plan", plan, 30, "Pick from this list for your 5 pm snack when you are bored of "
                                               "sprouts."), seen=False),
            dict(id="welcome", kind="article", title="Welcome to Train With Vimal", by=vimal, mins=2,
                 description="How the app works, how to log, and how to reach your coach.",
                 body="Your coach builds your training and meal plan. You will find both in the app every day."
                      "\n\nLog your workouts and food as you go. It takes a few seconds and helps your coach "
                      "adjust your plan.\n\nEvery Sunday you send a weekly check-in. Your coach replies within "
                      "a day.",
                 everyone=True, seen=True, done=True),
            dict(id="checkins", kind="pdf", title="How check-ins work", by=vimal,
                 description="Daily check-ins take 30 seconds. Weekly check-ins go to your coach every Sunday.",
                 outline=[["Daily check-in", "Sleep, energy, hunger and steps. 30 seconds a day."],
                          ["Weekly check-in", "Weight, how the week went and, every 2 weeks, photos and "
                                              "measurements."],
                          ["Progress photos", "Front, side and back, same light and same time of day."]],
                 everyone=True, seen=True, done=True),
        ]
        for x in items:
            it = ContentItem(kind=x["kind"], title=x["title"], description=x["description"], created_by=x["by"],
                             share_everyone=x.get("everyone", False), chapters=x.get("chapters", []),
                             outline=x.get("outline", []), body=x.get("body", ""), read_minutes=x.get("mins"),
                             duration_seconds=x.get("dur"), pages=len(x["outline"]) if "outline" in x else None)
            if x["kind"] == "pdf":
                it.file = _pdf(x["id"], x["title"], x["outline"])
            elif x["kind"] == "image":
                it.file = _snack_card(x["title"], x["tiles"])
            elif x["kind"] == "video":
                it.file = _video(x["id"], x["dur"])
            it.save()
            if x.get("everyone"):
                ContentItem.objects.filter(id=it.id).update(created_at=timezone.now() - timedelta(days=200))
            if "share" in x:
                src, label, ago, note = x["share"]
                sh = ContentShare.objects.create(item=it, client=riya, shared_by=aman,
                                                 note=note, source=src, source_label=label)
                ContentShare.objects.filter(id=sh.id).update(created_at=timezone.now() - timedelta(days=ago))
            if x.get("seen"):
                ContentView.objects.create(item=it, user=riya, finished=x.get("done", False),
                                           saved=x.get("saved", False), progress=100 if x.get("done") else 0)
        _file_content()
        del today

    def riya_checkins(self):
        """Check-ins board: six weekly check-ins (one missed, one waiting for Aman, two with a reply) and the
        last 10 days of daily check-ins (two missed, one with a reply). Today's daily one is still due."""
        from apps.accounts.models import User
        from apps.checkins.models import Answer, Form, Submission, WeightLog
        from apps.checkins.services import submit

        riya = User.objects.filter(email__iexact="riya@example.com").select_related("client_profile").first()
        weekly = Form.objects.filter(type="weekly", status="published").prefetch_related("questions").first()
        daily = Form.objects.filter(type="daily", status="published").prefetch_related("questions").first()
        if riya is None or weekly is None or daily is None or riya.client_profile.trainer is None:
            return
        if Answer.objects.filter(submission__client=riya, submission__form_type="weekly").exists():
            return
        Submission.objects.filter(client=riya, form_type__in=["weekly", "daily"]).delete()
        aman, today = riya.client_profile.trainer, timezone.localdate()
        cp = riya.client_profile
        current = cp.current_weight_kg

        def at(day, hh, mm):
            return timezone.make_aware(timezone.datetime.combine(day, timezone.datetime.min.time())) \
                + timedelta(hours=hh, minutes=mm)

        def answers(form, by_metric, by_text):
            out = {}
            for q in form.questions.all():
                if q.is_removed:
                    continue
                v = by_metric.get(q.metric) if q.metric else by_text.get(q.text)
                if v is not None:
                    out[str(q.id)] = v
            return out

        last_sunday = today - timedelta(days=today.weekday() + 1)
        # (weeks back, weight, week 1-5, meal plan, note, sent hh:mm, review)
        weeks = [(5, 71.8, 3, "Mostly, ate out once or twice", "", (17, 5), ("reviewed", "")),
                 (4, 71.2, 3, "Mostly, ate out once or twice", "", (17, 40), ("reviewed", "")),
                 (3, 70.6, 4, "Yes, all week", "Can I swap lunges for something easier on the knee?", (17, 40),
                  ("reply", "Great progress on the waist. Keep the steps up.")),
                 (1, 69.5, 4, "Yes, all week", "", (18, 0),
                  ("reply", "Great week, Riya. Your squat looks much better. Keep the protein up on rest days too.")),
                 (0, 68.9, 4, "Mostly, ate out once or twice", "Office travel next week, Tue to Thu", (17, 15),
                  None)]
        for back, kg, wk, meal, note, (hh, mm), rev in weeks:
            day = last_sunday - timedelta(days=7 * back)
            sub = submit(riya, weekly, answers(weekly, {"weight": kg}, {
                "How was your week?": wk, "Did you follow the meal plan?": meal,
                "Anything your coach should know?": note or None}), day=day)
            fields = {"created_at": at(day, hh, mm)}
            if rev:
                fields.update(reviewed_at=at(day + timedelta(days=1), 10, 15), reviewed_by=aman, reply=rev[1])
            Submission.objects.filter(id=sub.id).update(**fields)
        # Daily: (days back, sleep, energy, mood, hunger, soreness, note, reply)
        days = [(10, "7 h", 4, 4, 3, 4, "", ""), (9, "6.5 h", 3, 3, 3, 2, "Right knee sore",
                                                  "Rest the knee today, walk 30 min."),
                (8, "8 h", 5, 5, 2, 5, "", ""), (6, "7 h", 4, 4, 3, 4, "", ""),
                (5, "7.5 h", 4, 4, 3, 4, "Felt strong today", ""), (4, "6 h", 2, 3, 4, 3, "Late office, ate out", ""),
                (2, "7 h", 4, 4, 3, 4, "", ""), (1, "7.5 h", 4, 4, 3, 4, "Felt strong today", "")]
        for back, sleep, e, m, h, so, note, reply in days:
            day = today - timedelta(days=back)
            w = WeightLog.objects.filter(client=riya, date__lte=day).order_by("-date").first()
            kg = float(w.weight_kg) - 0.1 * (back % 3) if w else 70
            sub = submit(riya, daily, answers(daily, {"weight": round(kg, 1), "sleep_hours": sleep, "energy": e,
                                                       "mood": m, "hunger": h, "soreness": so}, {}),
                         note=note, day=day)
            fields = {"created_at": at(day, 8, 5 + back)}
            if reply:
                fields.update(reviewed_at=at(day, 10, 15), reviewed_by=aman, reply=reply)
            Submission.objects.filter(id=sub.id).update(**fields)
        latest = WeightLog.objects.filter(client=riya).order_by("-date").first()
        cp.current_weight_kg = latest.weight_kg if latest else current
        cp.save(update_fields=["current_weight_kg"])

    def aman_dashboard(self, program, plan):
        """Trainer dashboard board: Aman's day. Five new clients (two start this week, one stopped logging, two
        missed workouts), today's five sessions, earlier sessions this week, weekly check-ins waiting, and
        Rohan's plan ending on Sunday."""
        from apps.accounts.models import AccountStatus, Role, User
        from apps.checkins.models import Form, Submission
        from apps.checkins.services import submit
        from apps.clients.models import ClientProfile
        from apps.clients.metrics import refresh_client_stats
        from apps.nutrition.models import MealPlanAssignment, WaterLog
        from apps.nutrition.services import mark_eaten
        from apps.scheduling.models import Session
        from apps.training.models import AssignmentStatus, ProgramAssignment

        aman = User.objects.filter(email__iexact="aman@trainwithvimal.com").first()
        if aman is None or Session.objects.filter(trainer=aman, title="Push A").exists():
            return
        today, now = timezone.localdate(), timezone.now()
        monday = today - timedelta(days=today.weekday())
        weekly = Form.objects.filter(type="weekly", status="published").prefetch_related("questions").first()
        # name, email, gender, start (days ago), how they log: steady | quiet | missing
        people = [("Neha Jain", "neha.jain@example.com", "female", (today - monday).days, "steady"),
                  ("Aditya Rao", "aditya@example.com", "male", (today - monday).days, "steady"),
                  ("Vikram Singh", "vikram.singh@example.com", "male", 35, "missing"),
                  ("Kabir Anand", "kabir@example.com", "male", 42, "quiet"),
                  ("Tanya Arora", "tanya@example.com", "female", 28, "missing")]
        users = {}
        for i, (name, email, gender, ago, mode) in enumerate(people):
            u, made = self.user(email=email, phone=f"+91983000{i:04d}", full_name=name, role=Role.CLIENT,
                                status=AccountStatus.ACTIVE, gender=gender, city="Delhi")
            users[name] = u
            if not made:
                continue
            start = today - timedelta(days=ago)
            ClientProfile.objects.create(user=u, trainer=aman, goal="fat_loss" if gender == "female" else "muscle_gain",
                                         height_cm=165 if gender == "female" else 177, start_weight_kg=70,
                                         current_weight_kg=69, target_weight_kg=64, start_date=start,
                                         package_name="3 months · Gym", package_ends_on=start + timedelta(days=90),
                                         onboarding_done=["account", "basics", "goal_body", "health", "food"],
                                         ask_parq=False)
            pa = ProgramAssignment.objects.create(client=u, program=program, start_date=start,
                                                  status=AssignmentStatus.ACTIVE, assigned_by=aman)
            MealPlanAssignment.objects.create(client=u, plan=plan, start_date=start, assigned_by=aman)
            for back in range(min(ago, 21), 0, -1):
                day = today - timedelta(days=back)
                if mode == "quiet" and back < 8 or mode == "missing" and day >= monday:
                    continue
                WaterLog.objects.update_or_create(client=u, date=day, defaults={"ml": 2500})
                for meal in plan.meals.all():
                    mark_eaten(u, meal, day)
                if day.weekday() < program.days_per_week:
                    self.workout(u, pa, program, day)
            if mode == "quiet":
                User.objects.filter(id=u.id).update(last_seen_at=now - timedelta(days=7))
            refresh_client_stats(u.client_profile)

        rohan = User.objects.filter(email__iexact="rohan@example.com").first()
        riya = User.objects.filter(email__iexact="riya@example.com").first()
        sana = User.objects.filter(email__iexact="sana@example.com").first()
        if rohan:  # Plan ending: Rohan's program ends this Sunday and nothing is up next.
            ProgramAssignment.objects.filter(client=rohan, status=AssignmentStatus.ACTIVE).update(
                end_date=monday + timedelta(days=6))

        def at(day, hh, mm):
            return timezone.make_aware(timezone.datetime.combine(day, timezone.datetime.min.time())) \
                + timedelta(hours=hh, minutes=mm)

        # Today: (client, hh, mm, minutes, title, video call)
        plan_today = [(rohan, 7, 0, 60, "Push A", False), (users["Neha Jain"], 8, 30, 45, "Lower body", False),
                      (users["Vikram Singh"], 19, 30, 60, "Strength test", False),
                      (sana, 20, 45, 30, "Form check", True)]
        for c, hh, mm, mins, title, call in plan_today:
            if c is None:
                continue
            start = at(today, hh, mm)
            Session.objects.create(client=c, trainer=aman, title=title, start=start, end=start + timedelta(minutes=mins),
                                   is_call=call, place="" if call else "Gym floor",
                                   call_link="https://meet.google.com/abc-defg-hij" if call else "",
                                   status="done" if start + timedelta(minutes=mins) < now else "booked", booked_by=aman)
        # Earlier this week: most held, one missed.
        for back, c, title, st in [(1, rohan, "Pull A", "done"), (2, users["Aditya Rao"], "Intro session", "done"),
                                   (3, users["Tanya Arora"], "Lower body", "missed"), (3, riya, "Upper A", "done")]:
            day = today - timedelta(days=back)
            if c is None or day < monday:
                continue
            start = at(day, 18, 0)
            Session.objects.create(client=c, trainer=aman, title=title, start=start, end=start + timedelta(minutes=60),
                                   place="Gym floor", status=st, booked_by=aman)

        def answers(by_metric, by_text):
            out = {}
            for q in weekly.questions.all():
                if q.is_removed:
                    continue
                v = by_metric.get(q.metric) if q.metric else by_text.get(q.text)
                if v is not None:
                    out[str(q.id)] = v
            return out

        # Weekly check-ins waiting: (client, hours ago, weight, week 1-5, meal plan, note)
        if weekly:
            for c, hours, kg, wk, meal, note in [
                    (rohan, 26, 70.4, 5, "Yes, all week", "Bench felt strong. Can we add one more arm day?"),
                    (users["Tanya Arora"], 6, 66.2, 2, "No, it was a hard week", "Exams this week, very tired."),
                    (users["Kabir Anand"], 3, 78.0, 3, "Mostly, ate out once or twice", "")]:
                if c is None:
                    continue
                sub = submit(c, weekly, answers({"weight": kg}, {"How was your week?": wk,
                                                                 "Did you follow the meal plan?": meal,
                                                                 "Anything your coach should know?": note or None}),
                             day=today)
                Submission.objects.filter(id=sub.id).update(created_at=now - timedelta(hours=hours))
        # Feeling low: Tanya's last two daily check-ins.
        daily = Form.objects.filter(type="daily", status="published").prefetch_related("questions").first()
        tanya = users["Tanya Arora"]
        if daily:
            for back in (2, 1):
                vals = {}
                for q in daily.questions.all():
                    if q.metric == "weight":
                        vals[str(q.id)] = 66.3
                    elif q.metric == "sleep_hours":
                        vals[str(q.id)] = q.options[1] if q.options else "5 h"
                    elif q.metric in ("energy", "mood"):
                        vals[str(q.id)] = 2
                    elif q.metric:
                        vals[str(q.id)] = 3
                sub = submit(tanya, daily, vals, day=today - timedelta(days=back))
                Submission.objects.filter(id=sub.id).update(created_at=at(today - timedelta(days=back), 8, 0),
                                                            reviewed_at=at(today - timedelta(days=back), 9, 0),
                                                            reviewed_by=aman)

    def onboarding_answers(self):
        """Every demo client who finished setup has filled the gym's coaching form (D-36): the answers sit on the
        profile, the onboarding steps are done, the form's measurements are the first ones and the start photos
        are there. Runs again safely: a client who already agreed to the terms is left as they are."""
        from apps.accounts.models import AccountStatus, Role, User
        from apps.checkins.models import Measurement, PhotoSet, ProgressPhoto
        from apps.clients.models import CLIENT_ONBOARDING_STEPS
        from apps.clients.onboarding import FIELDS, USER_ATTRS

        tints = [((219, 230, 252), (88, 120, 220)), ((220, 240, 228), (70, 150, 100)),
                 ((236, 228, 250), (140, 110, 210)), ((252, 236, 220), (210, 140, 70))]
        people = (User.objects.filter(role=Role.CLIENT, status=AccountStatus.ACTIVE,
                                      client_profile__terms_agreed_at__isnull=True)
                  .select_related("client_profile").order_by("date_joined", "email"))
        for i, u in enumerate(people):
            cp = u.client_profile
            if len(cp.onboarding_done or []) < 5:
                continue  # still doing setup (Isha, Sana): nothing to fill in
            a = _onboarding_persona(u, cp, i)
            start = cp.start_date or timezone.localdate(u.date_joined)
            if not u.date_of_birth:
                u.date_of_birth = a.pop("date_of_birth")
                u.save(update_fields=["date_of_birth"])
            a.pop("date_of_birth", None)
            measures = a.pop("measures")
            first = Measurement.objects.filter(client=u).order_by("date").first()
            if first is None:
                first = Measurement.objects.create(client=u, date=start, values=measures)
            if not PhotoSet.objects.filter(client=u).exists():
                ps = PhotoSet.objects.create(client=u, date=start, label="Start photos", weight_kg=cp.start_weight_kg)
                for pose in ("front", "side", "back"):
                    ProgressPhoto.objects.create(photo_set=ps, pose=pose,
                                                 image=_figure(f"{pose}.jpg", *tints[i % len(tints)], pose))
            for k, v in a.items():
                if k == "health_notes" and cp.health_notes:
                    continue
                setattr(cp, k, v)
            # What the setup steps keep, step by step (photos are the poses, measurements their day).
            on = {k: v for k, v in (cp.onboarding or {}).items() if k.startswith("_")}
            for f in FIELDS:
                if f.kind == "photo":
                    on.setdefault("body", {}).setdefault("photos", []).append(f.key[6:])
                    continue
                if f.kind == "measure":
                    v = measures.get(f.key[8:])
                elif f.kind == "agree":
                    v = True
                elif f.key in USER_ATTRS:
                    v = getattr(u, f.key)
                    v = v.isoformat() if hasattr(v, "isoformat") else (v or "prefer_not")
                elif f.key == "weight_kg":
                    v = float(cp.start_weight_kg) if cp.start_weight_kg is not None else None
                else:
                    v = getattr(cp, f.attr or f.key)
                    v = float(v) if isinstance(v, Decimal) else v
                on.setdefault(f.step, {})[f.key] = v
            on["body"]["measured_on"] = first.date.isoformat()
            on["health"].update({"injuries": cp.injury_areas, "notes": cp.health_notes})
            on["food"]["diet"] = cp.diet_type
            on["agree"]["extra"] = {}
            assert set(CLIENT_ONBOARDING_STEPS) <= set(on)
            cp.onboarding = on
            cp.terms_agreed_at = timezone.make_aware(timezone.datetime.combine(start, timezone.datetime.min.time())) \
                - timedelta(days=1) + timedelta(hours=20)
            cp.save()

    def automations(self, vimal):
        """Admin → Automations (board `Automations`): five flows with a few clients already in them.
        Weekly check-in stays off here because the client app already sends that form every week."""
        from apps.automations.models import Automation, AutomationRun, Step
        from apps.checkins.models import Form
        from apps.notifications.models import NotificationSettings

        NotificationSettings.objects.filter(pk=NotificationSettings.load().pk, whatsapp_number="").update(
            whatsapp_number="+91 98200 12345")  # Emails & alerts → Sender (board value)
        if Automation.all_objects.exists():
            return
        forms = {f.name: str(f.id) for f in Form.objects.filter(client__isnull=True).exclude(status="client")}

        def form(name, ch):
            return ("form", {"form": forms.get(name, ""), "form_name": name, "channels": ch})

        def msg(key, ch):
            return ("message", {"template": key, "channels": ch})

        def wait(days=0, hours=0):
            return ("wait", {"days": days, "hours": hours})

        def task(title, who="trainer"):
            return ("task", {"title": title, "assignee": who, "due_days": 1})

        flows = [
            ("Client onboarding", "on", "client_approved", {}, "", True,
             [form("New client questionnaire", ["push", "email"]), wait(1),
              msg("onboarding-form-reminder", ["whatsapp"]), wait(2), task("Call the client about the onboarding form")]),
            ("Weekly check-in", "off", "every_week", {"weekday": 6, "time": "09:00"}, "3 months · Gym", True,
             [form("Weekly check-in", ["push", "whatsapp"]), wait(hours=24), msg("checkin-reminder", ["push", "whatsapp"]),
              task("Review the weekly check-in")]),
            ("Missed workouts nudge", "off", "missed_workouts", {"count": 3}, "", True,
             [msg("missed-workouts-nudge", ["push", "in_app"]), wait(2), task("Call the client")]),
            ("Renewal reminder", "on", "package_ending", {"days_before": 7, "time": "09:00"}, "", False,
             [msg("renewal-reminder", ["email", "whatsapp"]), wait(4), msg("renewal-reminder", ["whatsapp"]), wait(1),
              task("Talk about renewal")]),
            ("Birthday wish", "draft", "birthday", {"time": "09:00"}, "", False,
             [msg("birthday-wish", ["push", "whatsapp"]), task("Wish the client a happy birthday")]),
        ]
        made = {}
        for name, status, trig, cfg, pkg, stop, steps in flows:
            a = Automation.objects.create(name=name, status=status, trigger=trig, trigger_config=cfg, scope_package=pkg,
                                          stop_on_response=stop, created_by=vimal)
            for i, (kind, c) in enumerate(steps):
                Step.objects.create(automation=a, kind=kind, config=c, order=i)
            made[name] = a
        now = timezone.now()
        runs = [
            ("Client onboarding", "riya@example.com", "stopped", 1, "Sent the form · stopped at step 1", 2 * 24),
            ("Client onboarding", "kavya@example.com", "waiting", 2, "Wait 1 day", 5),
            ("Client onboarding", "ishaan@example.com", "finished", 5, "Trainer task made", 3 * 24),
            ("Client onboarding", "priya@example.com", "finished", 5, "Trainer task made", 6 * 24),
            ("Renewal reminder", "dev@example.com", "waiting", 2, "Wait 4 days", 26),
            ("Renewal reminder", "pooja@example.com", "finished", 5, "Trainer task made", 9 * 24),
        ]
        from apps.accounts.models import User

        for name, email, status, idx, last, hours_ago in runs:
            c = User.objects.filter(email=email).first()
            if c is None:
                continue
            at = now - timedelta(hours=hours_ago)
            r = AutomationRun.objects.create(
                automation=made[name], client=c, status=status, step_index=idx, dedupe_key="demo", last_message=last,
                next_run_at=at + timedelta(days=1) if status == "waiting" else None,
                finished_at=at if status in ("finished", "stopped") else None)
            AutomationRun.objects.filter(id=r.id).update(created_at=at - timedelta(days=1), updated_at=at)

    def settle_old_rows(self):
        """Everything the demo made at once looks "added this week". Clients and plans that started before this
        Monday get their created date moved back to their start, so the trainer's "This week" card counts right."""
        from apps.clients.models import ClientProfile
        from apps.nutrition.models import MealPlanAssignment
        from apps.training.models import ProgramAssignment

        today = timezone.localdate()
        monday = today - timedelta(days=today.weekday())
        old = timezone.now() - timedelta(days=today.weekday() + 21)
        ClientProfile.objects.filter(created_at__gte=old).exclude(start_date__gte=monday).update(created_at=old)
        for M in (ProgramAssignment, MealPlanAssignment):
            M.objects.filter(created_at__gte=old, start_date__lt=monday).update(created_at=old)

    def workout(self, client, assignment, program, day):
        from apps.training.models import SetLog, WorkoutLog

        week = program.program_weeks.order_by("number").first()
        pday = week.days.filter(weekday=day.weekday(), is_rest=False).prefetch_related("exercises__exercise").first()
        if pday is None or WorkoutLog.objects.filter(client=client, date=day).exists():  # one workout a day
            return
        start = timezone.make_aware(timezone.datetime.combine(day, timezone.datetime.min.time())) + timedelta(hours=7)
        w = WorkoutLog.objects.create(client=client, assignment=assignment, program_day=pday, name=pday.name, date=day,
                                      status=WorkoutLog.Status.COMPLETED, started_at=start,
                                      finished_at=start + timedelta(minutes=55), duration_seconds=55 * 60,
                                      effort=random.choice([6, 7, 8]))
        sets = []
        for pe in pday.exercises.all():
            base = Decimal(random.choice([20, 30, 40, 50, 60]))
            for n in range(1, pe.sets + 1):
                bw = pe.exercise.log_type == "bodyweight_reps"
                sets.append(SetLog(workout=w, program_exercise=pe, exercise=pe.exercise, set_number=n,
                                   weight_kg=None if bw else base, reps=random.choice([8, 9, 10]), is_bodyweight=bw,
                                   done=True, done_at=start + timedelta(minutes=3 * len(sets))))
        SetLog.objects.bulk_create(sets)
        w.sets_done = w.sets_planned = len(sets)
        w.save(update_fields=["sets_done", "sets_planned"])


# Coaching form answers for the demo clients (D-36). Riya and Aditya as on the boards; the others are picked from
# the pools by their place in the list, so every profile reads like a real person and none is the same.
PERSONAS = {
    "riya@example.com": dict(
        date_of_birth="1997-03-14", goal_detail="Lose belly fat before my sister's wedding in March",
        experience="beginner", enrolled_for="3", workout_days=5, workout_place="gym", workout_time="evening",
        current_exercise="Walk 30 min most days, yoga on Sundays", activity_level="sedentary",
        injury_areas=["none"], conditions=["none"], doctor_ok=True,
        past_injuries="Sprained left ankle in 2019, fully healed", surgeries="None", addictions="None",
        digestive_issues="Bloating after rajma or chole at night",
        stresses="Work deadlines\nSleeping late after office calls\nManaging home and office together",
        diet_type="egg", common_foods="Poha, roti, dal, sabzi, curd, eggs, fruit, 2 cups of tea",
        food_allergies="no", smoking="no",
        meal_breakfast="Poha or 2 egg omelette with toast, tea", meal_mid_morning="1 fruit, tea",
        meal_lunch="2 roti, dal, sabzi, curd", meal_pre_workout="Banana and black coffee",
        meal_post_workout="Whey protein in water", meal_evening="Roasted chana, tea",
        meal_dinner="2 roti, paneer or egg bhurji, salad",
        takes_supplements=True, supplements_detail="Whey protein, 1 scoop after workout, for protein",
        supplement_brands="MuscleBlaze Biozyme Whey", open_to_supplements="yes", takes_medicines=False,
        medicines_detail="", onboarding_note="I travel for work one week every month.",
        measures={"neck": 32, "bicep_l": 29.5, "bicep_r": 30, "chest": 93, "abdomen": 90, "waist": 84, "hips": 102,
                  "thigh_l": 58, "thigh_r": 58.5, "calf_l": 36, "calf_r": 36.5}),
    "aditya@example.com": dict(
        date_of_birth="1999-07-02", goal_detail="Gain size in chest and arms, stay lean", experience="intermediate",
        enrolled_for="6", workout_days=5, workout_place="gym", workout_time="early_morning",
        current_exercise="Gym 3 days a week: push, pull, legs", activity_level="moderate", injury_areas=["none"],
        conditions=["none"], doctor_ok=True, past_injuries="Right shoulder strain in 2023 from bench press, healed",
        surgeries="None", addictions="None", digestive_issues="None",
        stresses="Final year exams\nFamily business work on weekends\nIrregular sleep",
        diet_type="non_veg", common_foods="Eggs, chicken, rice, roti, dal, milk, banana", food_allergies="no",
        smoking="no", meal_breakfast="4 egg whites, 2 whole eggs, 2 toast, milk", meal_mid_morning="Banana, almonds",
        meal_lunch="Rice, chicken curry, dal, salad", meal_pre_workout="Peanut butter toast, black coffee",
        meal_post_workout="Whey protein with milk, banana", meal_evening="Sprouts chaat",
        meal_dinner="3 roti, chicken or paneer, sabzi", takes_supplements=True,
        supplements_detail="Whey after workout daily, creatine 5 g daily for strength",
        supplement_brands="Optimum Nutrition Gold Standard, MuscleBlaze Creatine", open_to_supplements="yes",
        takes_medicines=False, medicines_detail="", onboarding_note="",
        measures={"neck": 37, "bicep_l": 33, "bicep_r": 33.5, "chest": 98, "abdomen": 82, "waist": 80, "hips": 94,
                  "thigh_l": 55, "thigh_r": 55.5, "calf_l": 36, "calf_r": 36}),
}
_POOL = {
    "goal_detail": ["Fit into my old jeans", "Get stronger for football", "More energy at work", "Look good for photos",
                    "Bench press 100 kg", "Bring my sugar levels down"],
    "experience": ["beginner", "intermediate", "advanced", "intermediate"],
    "enrolled_for": ["3", "6", "3", "4", "5", "12 months"],
    "workout_days": [5, 4, 6, 5, 3],
    "workout_place": ["gym", "home", "gym", "both"],
    "workout_time": ["early_morning", "evening", "late_night", "afternoon", "evening"],
    "current_exercise": ["Not performing", "Walk 45 min every morning", "Gym 4 days a week",
                         "Cricket on weekends", "Home workouts from YouTube, 3 days a week"],
    "activity_level": ["sedentary", "light", "moderate", "active", "sedentary"],
    "past_injuries": ["None", "Left knee pain after running in 2022", "Wrist sprain in 2021, healed",
                      "Lower back strain lifting boxes last year"],
    "surgeries": ["None", "Appendix removed in 2018", "None", "Knee arthroscopy in 2020"],
    "addictions": ["None", "Social drinking on weekends", "None", "Too much tea, 5 cups a day"],
    "digestive_issues": ["None", "Acidity if I skip breakfast", "Gas after milk", "None"],
    "stresses": ["Office targets\nLong commute\nSleep", "Exams\nMoney\nFamily health",
                 "New job\nLate nights\nNo time to cook", "Business travel\nKids' schedule\nEating out"],
    "diet_type": ["veg", "non_veg", "egg", "jain", "non_veg", "vegan"],
    "common_foods": ["Roti, dal, rice, sabzi, curd, tea", "Eggs, chicken, rice, roti, milk",
                     "Paratha, paneer, dal, fruit, buttermilk", "Idli, dosa, sambar, rice, curd"],
    "food_allergies": ["no", "no", "Peanuts", "no", "Lactose, milk upsets my stomach"],
    "smoking": ["no", "no", "no", "Yes, 3 a day"],
    "meal_breakfast": ["Poha with tea", "Eggs and toast", "Paratha with curd", "Idli sambar", "Oats with milk"],
    "meal_mid_morning": ["Fruit", "Buttermilk", "Nothing", "Biscuits with tea"],
    "meal_lunch": ["Roti, dal, sabzi, rice", "Rice, chicken curry, salad", "Office canteen thali", "Rajma chawal"],
    "meal_pre_workout": ["Banana", "Black coffee", "Nothing", "Dates and coffee"],
    "meal_post_workout": ["Whey protein", "Milk and banana", "Sprouts", "Nothing"],
    "meal_evening": ["Tea and namkeen", "Roasted makhana", "Fruit", "Samosa sometimes"],
    "meal_dinner": ["Roti, sabzi, dal", "Rice, fish curry", "Khichdi", "Paneer bhurji, roti"],
    "takes_supplements": [False, True, False, True],
    "supplements_detail": ["", "Whey protein after workout, daily, for protein", "",
                           "Multivitamin every morning, doctor suggested"],
    "supplement_brands": ["", "Optimum Nutrition", "", "HealthKart HK Vitals"],
    "open_to_supplements": ["yes", "yes", "Only natural ones", "no"],
    "takes_medicines": [False, False, True, False],
    "medicines_detail": ["", "", "Thyronorm 50 mcg every morning for 2 years", ""],
    "onboarding_note": ["", "I work night shifts twice a week.", "", "Vegetarian on Tuesdays."],
}


def _onboarding_persona(user, cp, i):
    """The coaching form answers of one demo client (PERSONAS, else from the pools)."""
    from datetime import date

    p = PERSONAS.get(user.email)
    if p is not None:
        out = dict(p)
        out["date_of_birth"] = date.fromisoformat(out["date_of_birth"])
        out["measures"] = dict(out["measures"])
        return out
    out = {k: v[i % len(v)] for k, v in _POOL.items()}
    out["injury_areas"] = [["none"], ["knee"], ["none"], ["lower_back"], ["none"]][i % 5]
    out["conditions"] = [["none"], ["none"], ["thyroid"], ["none"]][i % 4] if not out["takes_medicines"] \
        else ["thyroid"]
    out["doctor_ok"] = True
    if out["injury_areas"] != ["none"]:
        out["health_notes"] = {"knee": "Right knee hurts on deep squats", "lower_back": "Lower back stiff after "
                               "sitting long"}[out["injury_areas"][0]]
    out["date_of_birth"] = date(1986 + i % 14, 1 + i % 12, 3 + i % 25)
    male = user.gender == "male"
    s = (cp.height_cm and float(cp.height_cm) / 170) or 1
    out["measures"] = {k: round(v * s, 1) for k, v in ({
        "neck": 38, "bicep_l": 32, "bicep_r": 32.5, "chest": 100, "abdomen": 92, "waist": 88, "hips": 98,
        "thigh_l": 56, "thigh_r": 56.5, "calf_l": 37, "calf_r": 37} if male else {
        "neck": 32, "bicep_l": 28, "bicep_r": 28.5, "chest": 90, "abdomen": 88, "waist": 80, "hips": 100,
        "thigh_l": 57, "thigh_r": 57.5, "calf_l": 35, "calf_r": 35.5}).items()}
    return out


def _figure(name, bg, fg, pose):
    """A plain drawn person on a soft colour: demo progress photos (no real pictures in the repo)."""
    from io import BytesIO

    from django.core.files.base import ContentFile
    from PIL import Image, ImageDraw

    im = Image.new("RGB", (360, 480), bg)
    d = ImageDraw.Draw(im)
    for y in range(480):  # light top-to-bottom wash
        k = y / 480 * 0.12
        d.line([(0, y), (360, y)], fill=tuple(int(c + (255 - c) * (0.12 - k)) for c in bg))
    cx = 180 + {"front": 0, "side": 8, "back": 0}[pose]
    d.ellipse([cx - 38, 90, cx + 38, 166], outline=fg, width=10)
    body = [cx - 78, 190, cx + 78, 420] if pose != "side" else [cx - 50, 190, cx + 50, 420]
    d.rounded_rectangle(body, radius=60, outline=fg, width=10)
    buf = BytesIO()
    im.save(buf, "JPEG", quality=82)
    return ContentFile(buf.getvalue(), name=name)


LEG_WARMUP = (
    "A good warm-up takes ten minutes and makes your first working set feel like your third. Do it in this "
    "order every leg day.\n\n"
    "## 1. Get warm (5 minutes)\n\n"
    "Easy cardio: bike, incline walk or skipping. You want to be warm and breathing a little faster, not tired.\n\n"
    "## 2. Open the hips\n\n"
    "- 10 leg swings each way, front to back and side to side\n- 8 slow hip circles each side\n"
    "- 30 seconds in a deep squat hold, elbows pushing the knees out\n\n"
    "## 3. Wake up the glutes\n\n"
    "- 2 sets of 15 glute bridges, squeeze at the top\n- 10 banded side steps each way\n\n"
    "## 4. Ramp up to your working weight\n\n"
    "Do 2 light sets of your first exercise: one with the empty bar for 10 reps, one at about half your working "
    "weight for 5. Then start your sets.\n\n"
    "If your knee feels sore, stay longer in step 2 and use box squats for the day."
)

SHIPPED_PDFS = {"Eating out on a fat loss plan": "eat"}


def _refresh_shipped_pdfs(model):
    """Older demo databases got a plain drawn PDF: swap in the designed one and drop the old page pictures."""
    from pathlib import Path

    from django.core.files.base import ContentFile
    from django.core.files.storage import default_storage

    for title, slug in SHIPPED_PDFS.items():
        shipped = Path(__file__).resolve().parents[2] / "demo_media" / f"{slug}.pdf"
        it = model.objects.filter(title=title, kind="pdf").first()
        if not shipped.exists() or it is None:
            continue
        data = shipped.read_bytes()
        try:
            if it.file and it.file.size == len(data):
                continue
        except OSError:  # the old file is gone from media: put the shipped one back
            pass
        for n in range(1, (it.pages or 0) + 1):
            name = f"content/pages/{it.id}/{n}.png"
            if default_storage.exists(name):
                default_storage.delete(name)
        it.file.save(f"{slug}.pdf", ContentFile(data), save=False)
        it.pages = None  # page pictures are drawn again on next open
        it.save(update_fields=["file", "pages"])


def _pdf(slug, title, pages):
    """A real PDF for the demo Library: the designed guide shipped in apps/common/demo_media/<slug>.pdf (made
    from <slug>.html with scripts/demo_pdf.js), else a plain one page per outline entry."""
    from io import BytesIO
    from pathlib import Path

    from django.core.files.base import ContentFile

    shipped = Path(__file__).resolve().parents[2] / "demo_media" / f"{slug}.pdf"
    if shipped.exists():
        return ContentFile(shipped.read_bytes(), name=f"{slug}.pdf")
    from PIL import Image, ImageDraw, ImageFont

    def font(n):
        for name in ("DejaVuSans.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "arial.ttf"):
            try:
                return ImageFont.truetype(name, n)
            except OSError:
                continue
        return ImageFont.load_default()

    out = []
    for i, (head, text) in enumerate(pages):
        im = Image.new("RGB", (595, 842), "white")
        d = ImageDraw.Draw(im)
        d.text((56, 56), title, fill=(110, 110, 110), font=font(14))
        d.text((56, 110), head, fill=(20, 20, 20), font=font(28))
        y, line = 170, ""
        for w in text.split():
            if d.textlength(line + " " + w, font=font(17)) > 480:
                d.text((56, y), line.strip(), fill=(50, 50, 50), font=font(17))
                y, line = y + 28, ""
            line += " " + w
        d.text((56, y), line.strip(), fill=(50, 50, 50), font=font(17))
        d.text((56, 790), f"Train With Vimal · page {i + 1} of {len(pages)}", fill=(150, 150, 150), font=font(12))
        out.append(im)
    buf = BytesIO()
    out[0].save(buf, "PDF", save_all=True, append_images=out[1:], resolution=72)
    return ContentFile(buf.getvalue(), name=f"{slug}.pdf")


def _snack_card(title, tiles):
    from io import BytesIO

    from django.core.files.base import ContentFile
    from PIL import Image, ImageDraw, ImageFont

    try:
        f1 = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 30)
        f2 = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 22)
    except OSError:
        f1 = f2 = ImageFont.load_default()
    im = Image.new("RGB", (900, 1100), (232, 245, 236))
    d = ImageDraw.Draw(im)
    d.text((50, 50), title, fill=(20, 80, 45), font=f1)
    for i, (n, k) in enumerate(tiles):
        x, y = 50 + (i % 2) * 410, 130 + (i // 2) * 185
        d.rounded_rectangle([x, y, x + 390, y + 165], radius=22, fill="white")
        d.text((x + 24, y + 40), n, fill=(30, 30, 30), font=f2)
        d.text((x + 24, y + 90), k, fill=(30, 120, 70), font=f2)
    buf = BytesIO()
    im.save(buf, "PNG")
    return ContentFile(buf.getvalue(), name="snacks.png")


def _hinge_card():
    """Demo exercise picture: three numbered steps of the hip hinge."""
    from io import BytesIO

    from django.core.files.base import ContentFile
    from PIL import Image, ImageDraw, ImageFont

    try:
        f1 = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 34)
        f2 = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 24)
    except OSError:
        f1 = f2 = ImageFont.load_default()
    im = Image.new("RGB", (1200, 675), (234, 240, 254))
    d = ImageDraw.Draw(im)
    d.text((60, 50), "Romanian deadlift · the hinge", fill=(29, 78, 216), font=f1)
    steps = [("1", "Stand tall, bar at the hips"), ("2", "Push the hips back, shins still"), ("3", "Squeeze glutes to stand")]
    for i, (n, t) in enumerate(steps):
        x = 60 + i * 370
        d.rounded_rectangle([x, 140, x + 340, 600], radius=28, fill="white")
        cx, top = x + 170, 220 + i * 25
        d.ellipse([cx - 26, top - 52, cx + 26, top], outline=(40, 40, 40), width=6)  # head
        lean = (0, 70, 130)[i] if i < 2 else 0
        d.line([cx, top, cx + lean, top + 150], fill=(40, 40, 40), width=8)  # back
        d.line([cx + lean, top + 150, cx + lean - 10, top + 300], fill=(40, 40, 40), width=8)  # legs
        d.line([cx, top + 40, cx + lean // 2, top + 170], fill=(37, 99, 235), width=8)  # arms to the bar
        d.text((x + 24, 520), f"{n}. {t}", fill=(30, 30, 30), font=f2)
    buf = BytesIO()
    im.save(buf, "PNG")
    return ContentFile(buf.getvalue(), name="hinge.png")


def _video(slug, seconds):
    """A small silent MP4 of the right length: the one shipped in apps/common/demo_media/<slug>.mp4, else made
    with ffmpeg (None when neither exists)."""
    import os
    import shutil
    import subprocess
    import tempfile
    from pathlib import Path

    from django.core.files.base import ContentFile

    shipped = Path(__file__).resolve().parents[2] / "demo_media" / f"{slug}.mp4"
    if shipped.exists():
        return ContentFile(shipped.read_bytes(), name=f"{slug}.mp4")
    if not shutil.which("ffmpeg"):
        return None
    with tempfile.TemporaryDirectory() as tmp:
        out = f"{tmp}/{slug}.mp4"
        font = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
        text = (f",drawtext=fontfile={font}:text='Train With Vimal · demo video':fontcolor=0x8a6d3b:fontsize=26"
                f":x=(w-tw)/2:y=h/2-40,drawtext=fontfile={font}:text='%{{pts\\:hms}}':fontcolor=0x8a6d3b"
                f":fontsize=22:x=(w-tw)/2:y=h/2+10") if os.path.exists(font) else ""
        cmd = ["ffmpeg", "-loglevel", "error", "-f", "lavfi", "-i", f"color=c=0xFFF1DE:s=640x360:r=5:d={seconds}",
               "-vf", "format=yuv420p" + text, "-c:v", "libx264", "-preset", "veryfast", "-crf", "30",
               "-movflags", "+faststart", out]
        if subprocess.run(cmd, check=False).returncode != 0:
            return None
        with open(out, "rb") as fh:
            return ContentFile(fh.read(), name=f"{slug}.mp4")


def _file_content():
    """Content library board: file the demo items under the default categories and record file sizes, so the
    rail counts and the storage bar have something to show. Only fills what is empty."""
    from apps.content.models import Category, ContentItem

    cats = {c.name: c for c in Category.objects.all()}
    by_word = [("welcome", "Onboarding"), ("check-in", "Onboarding"), ("eat", "Nutrition guides"),
               ("macro", "Nutrition guides"), ("snack", "Nutrition guides"), ("protein", "Nutrition guides"),
               ("warm up", "Form tutorials"), ("how to", "Form tutorials"), ("walkthrough", "Exercise videos")]
    for it in ContentItem.objects.filter(category__isnull=True):
        t = it.title.lower()
        name = next((c for w, c in by_word if w in t), "Exercise videos" if it.kind in ("video", "image") else None)
        if name in cats:
            ContentItem.objects.filter(id=it.id).update(category=cats[name])
    for it in ContentItem.objects.filter(file_size__isnull=True).exclude(file=""):
        try:
            ContentItem.objects.filter(id=it.id).update(file_size=it.file.size)
        except OSError:
            pass
