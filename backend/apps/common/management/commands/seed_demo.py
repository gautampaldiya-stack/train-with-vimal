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
            self.history(program, plan)
            self.riya_home()
            self.riya_train()
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
                                  actor=vimal)
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
                if not steady and back < 9:
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

    def workout(self, client, assignment, program, day):
        from apps.training.models import SetLog, WorkoutLog

        week = program.program_weeks.order_by("number").first()
        pday = week.days.filter(weekday=day.weekday(), is_rest=False).prefetch_related("exercises__exercise").first()
        if pday is None:
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
