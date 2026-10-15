"""The built-in weekly and daily check-ins ask what the Check-ins boards ask (decision D-19).

Only forms still holding the first template are changed. Questions that already have answers are hidden
(is_removed), so old check-ins stay readable."""
from django.db import migrations

OLD = {
    "weekly": ["Body weight (kg)", "How was your energy this week?", "How many of your planned meals did you follow?",
               "How did your workouts feel?", "Progress photos", "Anything you want changed in your plan?"],
    "daily": ["Weight (kg)", "Sleep last night", "Energy", "Mood", "Hunger", "Soreness"],
}
ENERGY = ["Very low", "Low", "Okay", "Good", "Great"]


def q(text, type, *, options=None, scale=None, help="", required=False, metric=""):
    return {"text": text, "type": type, "options": options or [], "scale_labels": scale or [], "help_text": help,
            "required": required, "metric": metric}


NEW = {
    "weekly": [
        q("Body weight (kg)", "number", help="Weigh in the morning, before you eat.", required=True, metric="weight"),
        q("How was your week?", "scale", scale=["Very hard", "Hard", "Okay", "Good", "Great"],
          help="1 is very hard, 5 is great.", required=True),
        q("Did you follow the meal plan?", "single",
          options=["Yes, all week", "Mostly, ate out once or twice", "No, it was a hard week"],
          help="Be honest, it helps {coach} plan your food.", required=True),
        q("Progress photos this week?", "photo", help="Front, side and back. Tap a slot to add a photo."),
        q("Anything your coach should know?", "long", help="Optional. Travel, injuries, stress, questions."),
    ],
    "daily": [
        q("Morning weight", "number", help="Empty stomach, same scale", required=True, metric="weight"),
        q("Sleep last night", "single", options=["5 h", "6 h", "6.5 h", "7 h", "7.5 h", "8 h", "9 h"],
          required=True, metric="sleep_hours"),
        q("Energy", "scale", scale=ENERGY, required=True, metric="energy"),
        q("Mood", "scale", scale=ENERGY, required=True, metric="mood"),
        q("Hunger", "scale", scale=["Very low", "Low", "Normal", "High", "Very high"], required=True,
          metric="hunger"),
        q("Soreness", "scale", scale=["Very sore", "Sore", "Some", "Light", "None"], required=True,
          metric="soreness"),
    ],
}


def forward(apps, schema_editor):
    Form = apps.get_model("checkins", "Form")
    Question = apps.get_model("checkins", "Question")
    Answer = apps.get_model("checkins", "Answer")
    for name, kind in [("Weekly check-in", "weekly"), ("Morning check-in", "daily")]:
        for form in Form.objects.filter(name=name, type=kind):
            qs = list(Question.objects.filter(form=form, is_removed=False).order_by("order"))
            if [x.text for x in qs] != OLD[kind]:
                continue
            for x in qs:
                if Answer.objects.filter(question=x).exists():
                    x.is_removed = True
                    x.save(update_fields=["is_removed"])
                else:
                    x.delete()
            Question.objects.bulk_create([Question(form=form, order=i, **d) for i, d in enumerate(NEW[kind])])


class Migration(migrations.Migration):
    dependencies = [("checkins", "0001_initial")]

    operations = [migrations.RunPython(forward, migrations.RunPython.noop)]
