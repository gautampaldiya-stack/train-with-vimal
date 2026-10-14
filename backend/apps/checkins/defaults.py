"""Standard questions for 'Create form → Template', and the built-in forms seeded on install."""

SCALE_ENERGY = ["Very low", "Low", "Okay", "Good", "Great"]
SCALE_HUNGER = ["Very low", "Low", "Normal", "High", "Very high"]
SCALE_SORE = ["Very sore", "Sore", "A bit", "Barely", "None"]


def q(text, type, *, options=None, scale=None, help="", required=False, metric="", other=False):
    return {"text": text, "type": type, "options": options or [], "scale_labels": scale or [], "help_text": help,
            "required": required, "metric": metric, "allow_other": other}


TEMPLATES = {
    "onboarding": [
        q("What is your main goal?", "single", options=["Lose fat", "Build muscle", "Get stronger", "Get fitter",
                                                       "Feel better"], required=True, other=True),
        q("How many days a week can you train?", "single", options=["2", "3", "4", "5", "6"], required=True),
        q("Where will you train?", "single", options=["Gym", "Home", "Both"], required=True),
        q("Have you trained before?", "single", options=["Never", "Less than a year", "1–3 years",
                                                         "More than 3 years"]),
        q("What do you eat?", "single", options=["Vegetarian", "Eggetarian", "Non-veg", "Vegan"], required=True),
        q("Foods you don't eat or are allergic to", "long"),
        q("Any injury, pain or health condition?", "long", help="Back pain, thyroid, recent surgery…"),
        q("What time do you usually wake up?", "short"),
        q("Your job is mostly…", "single", options=["Sitting", "Standing", "Moving a lot"]),
        q("Anything else your coach should know?", "long"),
    ],
    "weekly": [
        q("Body weight (kg)", "number", help="Weigh in the morning, before you eat.", required=True, metric="weight"),
        q("How was your energy this week?", "scale", scale=SCALE_ENERGY, metric="energy"),
        q("How many of your planned meals did you follow?", "single",
          options=["All of them", "Most", "About half", "Less than half"]),
        q("How did your workouts feel?", "long"),
        q("Progress photos", "photo", help="Same spot, same light, in the morning."),
        q("Anything you want changed in your plan?", "long"),
    ],
    "daily": [
        q("Weight (kg)", "number", help="Empty stomach, same scale", metric="weight"),
        q("Sleep last night", "scale", scale=["5 h", "6 h", "7 h", "8 h", "9 h"], metric="sleep_hours"),
        q("Energy", "scale", scale=SCALE_ENERGY, metric="energy"),
        q("Mood", "scale", scale=SCALE_ENERGY, metric="mood"),
        q("Hunger", "scale", scale=SCALE_HUNGER, metric="hunger"),
        q("Soreness", "scale", scale=SCALE_SORE, metric="soreness"),
    ],
    "survey": [
        q("How happy are you with your coaching?", "scale", scale=["Not at all", "A little", "Okay", "Happy",
                                                                     "Very happy"], required=True),
        q("What is working well?", "long"),
        q("What should we do better?", "long"),
    ],
    "waiver": [
        q("I confirm my health details are true and complete.", "yes_no", required=True),
        q("I understand exercise has risks and I train at my own risk.", "yes_no", required=True),
        q("I will tell my coach about any pain or new health problem.", "yes_no", required=True),
    ],
}

PARQ = [
    q("Has a doctor ever said you have a heart condition?", "yes_no", required=True),
    q("Do you feel pain in your chest when you do physical activity?", "yes_no", required=True),
    q("In the past month, have you had chest pain when not doing physical activity?", "yes_no", required=True),
    q("Do you lose your balance because of dizziness, or ever lose consciousness?", "yes_no", required=True),
    q("Do you have a bone or joint problem that activity could make worse?", "yes_no", required=True),
    q("Are you taking medicine for blood pressure or a heart condition?", "yes_no", required=True),
    q("Do you know any other reason you should not do physical activity?", "yes_no", required=True),
]

BUILTIN_FORMS = [
    ("New client questionnaire", "onboarding", TEMPLATES["onboarding"], False),
    ("PAR-Q health screening", "onboarding", PARQ, True),
    ("Weekly check-in", "weekly", TEMPLATES["weekly"], False),
    ("Morning check-in", "daily", TEMPLATES["daily"], False),
    ("Monthly feedback", "survey", TEMPLATES["survey"], False),
    ("Liability waiver", "waiver", TEMPLATES["waiver"], False),
]


def seed():
    from .models import Form, Question

    for name, type_, questions, is_parq in BUILTIN_FORMS:
        if Form.all_objects.filter(name=name).exists():
            continue
        f = Form.objects.create(name=name, type=type_, status=Form.Status.PUBLISHED, is_parq=is_parq)
        Question.objects.bulk_create([Question(form=f, order=i, **qd) for i, qd in enumerate(questions)])
