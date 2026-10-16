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
            self.riya_checkins()
            self.riya_progress()
            self.riya_library()
            self.exercise_media()
            self.library_link()
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
        """Exercise guide media: Leg Press and Walking Lunge get a demo video, Romanian Deadlift a picture.
        Not shared with clients, so they show in the guide only (not in the Library)."""
        from apps.accounts.models import User
        from apps.content.models import ContentItem
        from apps.training.models import Exercise

        vimal = User.objects.get(email="vimal@trainwithvimal.com")
        for name, kind, title, sec in [("Leg Press", "video", "Leg press: how to", 42),
                                       ("Walking Lunge", "video", "Walking lunge: how to", 55),
                                       ("Romanian Deadlift", "image", "Romanian deadlift: the hinge", 0)]:
            ex = Exercise.objects.filter(name=name, is_builtin=True).first()
            if ex is None or ex.video_id:
                continue
            f = _video(title.split(":")[0].lower().replace(" ", "-"), sec) if kind == "video" else _hinge_card()
            item = ContentItem.objects.create(kind=kind, title=title, created_by=vimal, duration_seconds=sec or None,
                                              description=f"How to do the {name.lower()} with good form.")
            if f is not None:
                item.file = f
                item.save()
            ex.video = item
            ex.save(update_fields=["video"])

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
                 body="Start with 5 minutes of easy cardio: bike, incline walk or skipping. You want to be warm, "
                      "not tired.\n\nOpen the hips: 10 leg swings each way, 8 hip circles and 30 seconds in a "
                      "deep squat hold.\n\nWake up the glutes with 2 sets of 15 glute bridges and 10 banded "
                      "side steps each way.\n\nFinish with 2 light sets of your first exercise before the "
                      "working weight.",
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


def _pdf(slug, title, pages):
    """A small real PDF, one page per outline entry (demo Library)."""
    from io import BytesIO

    from django.core.files.base import ContentFile
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
    """A small silent MP4 of the right length (needs ffmpeg; None without it)."""
    import os
    import shutil
    import subprocess
    import tempfile

    from django.core.files.base import ContentFile

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
