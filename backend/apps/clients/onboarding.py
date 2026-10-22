"""Client onboarding = the gym's coaching form (Gautam's "Online Training Form TWV", D-36), asked in steps.

One list, FIELDS, says for every answer: its key, the setup step that asks it, the kind of answer, the question
text, whether it is required and where it is kept. Everything else reads it:

- the setup steps (`me/onboarding/`) check and save each step with it, into ClientProfile / User fields
  (weight also as the first weigh-in, measurements as the first Measurement, photos as the "Start photos" set);
- Edit profile (`PATCH clients/<id>/`) accepts the same fields (`update_fields`);
- Overview → About (`about_items`) and Forms → Onboarding questionnaire (`answer_sections`) show them.

The onboarding questionnaire is also a Form the admin can edit ("New client questionnaire"). Its questions carry a
`profile_key` (a FIELDS key): a removed question is not asked in the app, a renamed one shows the new words, and a
question with no key is an extra one — the app asks it on the last step and its answer is kept with the onboarding
answers (`onboarding["agree"]["extra"]`, by question id)."""

import re
from dataclasses import dataclass, field
from datetime import date

from django.utils import timezone
from rest_framework import serializers

from .models import CLIENT_ONBOARDING_STEPS, Goal

# ---------------------------------------------------------------- options (key, label[, line])

LEVELS = [("beginner", "Beginner", "0 – 6 months"), ("intermediate", "Intermediate", "6 months – 2 years"),
          ("advanced", "Advanced", "2+ years")]
ENROLLED = [("3", "3 months"), ("4", "4 months"), ("5", "5 months"), ("6", "6 months")]
GENDERS = [("male", "Male"), ("female", "Female"), ("prefer_not", "Prefer not to say"), ("other", "Other")]
PLACES = [("gym", "Gym"), ("home", "Home"), ("both", "Gym and home")]
WORKOUT_TIMES = [("early_morning", "Early morning"), ("afternoon", "Afternoon"), ("evening", "Evening"),
                 ("late_night", "Late night")]
ACTIVITY = [
    ("sedentary", "Sedentary", "Desk job with little to no exercise"),
    ("light", "Little activity", "Exercise moderately 1–3 times a week. Or no exercise, but a slightly active job."),
    ("moderate", "Moderate", "Exercise moderately 2–3 times a week with a sedentary job. Or a slightly active job, "
                             "and exercise moderately 1–3 times a week."),
    ("active", "Active", "Physical work, hard exercise 5+ days a week"),
    ("very_active", "Highly active", "Physical work, exercise very hard 6+ days a week"),
]
# Answers saved before D-36 (3 activity levels) still read right.
OLD_ACTIVITY = {"desk": "Sedentary", "on_feet": "Little activity"}
INJURIES = [("none", "None"), ("knee", "Knee"), ("lower_back", "Lower back"), ("shoulder", "Shoulder"),
            ("neck", "Neck"), ("wrist", "Wrist"), ("ankle", "Ankle")]
CONDITIONS = [("none", "None"), ("diabetes", "Diabetes"), ("thyroid", "Thyroid"), ("high_bp", "High BP"),
              ("pcos", "PCOS"), ("asthma", "Asthma"), ("heart", "Heart condition")]
DIETS = [("non_veg", "Non-veg"), ("veg", "Veg, no egg"), ("egg", "Veg + eggs"), ("vegan", "Vegan"), ("jain", "Jain")]
NO = [("no", "No")]
YES_NO_OTHER = [("yes", "Yes"), ("no", "No")]
MEASURES = [("neck", "Neck"), ("bicep_l", "Left bicep"), ("bicep_r", "Right bicep"), ("chest", "Chest"),
            ("abdomen", "Abdomen from navel"), ("waist", "Waist (where you wear trousers)"), ("hips", "Hips"),
            ("thigh_l", "Left thigh"), ("thigh_r", "Right thigh"), ("calf_l", "Left calf"), ("calf_r", "Right calf")]
POSES = [("front", "Front"), ("side", "Right side"), ("back", "Back side")]

TERMS_TITLE = "Terms and conditions"
TERMS = """Please check every response carefully, as these details will be used to make your plans. And agree the terms and conditions. All details will be kept secrets and will not be disclosed to any one.

Terms and Conditions For Money Back Guarantee
• We need to make sure you have put in work at your end and updated us daily for the first 21 days with details.
• This would only be valid for the first 28 days after starting the plan (after the plan is delivered).
• You haven't seen any results in these days irrespective of following the plan. (For that you need to send in all daily and weekly check-ins on time. Missed check-ins would lead to the guarantee being void / cancelled.)
• If you are facing any issues with the service, that has been communicated. (Please communicate with us, so that we can resolve it for you ASAP.)

Terms and conditions
• We do not provide medical advice.
• Please consult a physician before starting any diet or workout program.
• Please disclose any medical issues (if any) before enrolling into any of our programmes.
• Please be respectful at all times with your coach.
• All transformations are a result of teamwork and there will be some ups and downs. We always have to work together as a team. We are always willing to give our 100% to help you transform. Our goal and mission for the time we work together would be to MAKE SURE YOU SUCCEED AND TRANSFORM.
• Please read the whole message as we are looking to work with you as a team and don't want you to hop on without full clarity on the program. If you have questions, feel free to get in touch with me.

Thank you
Let's shock the world with your transformation."""
AGREE = ("Yes, I have read everything carefully and I am signing this in full consciousness. I agree, I am "
         "participating in this of my own, no one is forcing me. I agree, I will fully cooperate in diet and workout "
         "whatever is told and explained to me, I will follow it properly. Results may vary and may take time. I "
         "agree, I will pay fees in advance. I agree to the terms and conditions that fee once paid is not refundable "
         "and adjustable in future. So I will not dispute that. If I fail in dieting or working out, then I am totally "
         "responsible for not getting any results.")


@dataclass
class F:
    key: str
    step: str
    kind: str  # goal choice other multi text long int num date phone gender yesno agree measure photo
    label: str  # the question, as on the gym's form
    section: str  # Forms → Onboarding questionnaire section
    req: bool = True
    options: list = field(default_factory=list)
    other: str = "Other"  # the chip that opens the client's own words (kind "other")
    lo: float = 0
    hi: float = 0
    max_len: int = 2000
    help: str = ""
    attr: str = ""  # profile attribute when it is not the key


BASIC, GOALS, TRAINING, HEALTH = "Basic information", "Goals", "Training", "Health"
FOOD, MEALS, SUPPS, BODY, LAST = ("Food and lifestyle", "Current schedule", "Supplements and medicines",
                                  "Measurements and photos", "Last from your side")
NONE_HELP = "Write None if there is nothing."

FIELDS = [
    F("goal", "goal", "goal", "Your specific goal", GOALS),
    F("goal_detail", "goal", "text", "Anything specific about your goal?", GOALS, req=False, max_len=200,
      help="For example: a wedding in March, lose belly fat"),
    F("experience", "goal", "choice", "Training experience", GOALS, options=LEVELS),
    F("enrolled_for", "about", "other", "You have enrolled for?", BASIC, options=ENROLLED, max_len=60),
    F("phone", "about", "phone", "Contact number", BASIC),
    F("date_of_birth", "about", "date", "Date of birth", BASIC),
    F("gender", "about", "gender", "Gender", BASIC, options=GENDERS),
    F("weight_kg", "about", "num", "Weight (in kg)", BASIC, lo=30, hi=250, attr="current_weight_kg"),
    F("height_cm", "about", "num", "Height (in cm)", BASIC, lo=100, hi=230),
    F("target_weight_kg", "about", "num", "Goal weight (in kg)", BASIC, req=False, lo=30, hi=250,
      help="Leave it empty if you are not sure. Your coach sets it with you."),
    F("workout_days", "training", "int", "How many days a week can you work out?", TRAINING, lo=1, hi=7,
      help="Minimum 5 days a week is preferred."),
    F("workout_place", "training", "other", "Where are you planning to work out?", TRAINING, options=PLACES,
      max_len=80),
    F("workout_time", "training", "other", "What time do you prefer for your workout?", TRAINING,
      options=WORKOUT_TIMES, max_len=80),
    F("current_exercise", "training", "long", "What are you currently doing for exercise?", TRAINING, max_len=1000,
      help='If nothing, write "Not performing".'),
    F("activity_level", "training", "choice", "Which describes your activity level?", TRAINING, options=ACTIVITY),
    F("injury_areas", "health", "multi", "Any injuries or pain right now?", HEALTH, options=INJURIES),
    F("health_notes", "health", "long", "Current injuries or restrictions", HEALTH, req=False,
      help="For example: cannot move the right arm in a circle."),
    F("past_injuries", "health", "long", "What injuries have you had in the past?", HEALTH, help=NONE_HELP),
    F("surgeries", "health", "long", "Any surgeries?", HEALTH, help=NONE_HELP),
    F("addictions", "health", "long", "Have you had, or do you have, any known addictions? (Alcohol, drugs, etc.)",
      HEALTH, help=NONE_HELP),
    F("conditions", "health", "multi", "Any health conditions?", HEALTH, options=CONDITIONS),
    F("doctor_ok", "health", "yesno", "A doctor has cleared me for exercise", HEALTH, req=False),
    F("digestive_issues", "health", "long", "Do you have any digestive issue? If yes, explain and name the food.",
      HEALTH, help=NONE_HELP),
    F("stresses", "health", "long", "List the 3 biggest stresses in your life", HEALTH,
      help="Let's see if we can work on it."),
    F("diet_type", "food", "other", "You are?", FOOD, options=DIETS, max_len=80),
    F("common_foods", "food", "long", "The foods you eat most through the day", FOOD),
    F("food_allergies", "food", "other", "Any known food allergies?", FOOD, options=NO, other="Yes", max_len=300,
      help="Name the food in detail."),
    F("smoking", "food", "other", "Do you smoke cigarettes?", FOOD, options=NO, other="Yes", max_len=120,
      help="If yes, how many a day?"),
    F("meal_breakfast", "meals", "long", "What do you have in breakfast?", MEALS, max_len=1000),
    F("meal_mid_morning", "meals", "long", "What do you have in between?", MEALS, max_len=1000,
      help="Between breakfast and lunch."),
    F("meal_lunch", "meals", "long", "What do you have in lunch?", MEALS, max_len=1000),
    F("meal_pre_workout", "meals", "long", "What do you have pre-workout?", MEALS, max_len=1000),
    F("meal_post_workout", "meals", "long", "What do you have post-workout?", MEALS, max_len=1000),
    F("meal_evening", "meals", "long", "What do you have in between?", MEALS, max_len=1000,
      help="Between lunch and dinner."),
    F("meal_dinner", "meals", "long", "What do you have in dinner?", MEALS, max_len=1000),
    F("takes_supplements", "supplements", "yesno", "Are you taking any supplements?", SUPPS),
    F("supplements_detail", "supplements", "long", "What, how often, and why are you taking it?", SUPPS, req=False),
    F("supplement_brands", "supplements", "long", "Brands of your supplements", SUPPS, req=False, max_len=1000,
      help="It helps your coach check the quality."),
    F("open_to_supplements", "supplements", "other", "Can you take supplements if your coach suggests them?", SUPPS,
      options=YES_NO_OTHER, max_len=120),
    F("takes_medicines", "supplements", "yesno", "Are you using any medicines?", SUPPS),
    F("medicines_detail", "supplements", "long", "Which medicines, and for how long?", SUPPS, req=False),
    *[F(f"measure_{k}", "body", "measure", label, BODY, lo=10, hi=250) for k, label in MEASURES],
    *[F(f"photo_{k}", "body", "photo", label, BODY) for k, label in POSES],
    F("onboarding_note", "agree", "long", "Any note? A medical problem or anything you want to tell your coach",
      LAST, req=False),
    F("terms", "agree", "agree", "I have read everything and I agree to the terms and conditions", LAST),
]
BY_KEY = {f.key: f for f in FIELDS}
USER_ATTRS = {"phone", "date_of_birth", "gender"}
# Fields Edit profile (PATCH clients/<id>/) takes on top of its own ones.
EDITABLE = [f for f in FIELDS if f.kind not in ("measure", "photo", "agree", "phone", "date", "gender", "goal")
            and f.key not in ("weight_kg", "height_cm", "target_weight_kg", "health_notes")]

# ---------------------------------------------------------------- the admin's form


def questionnaire():
    """The library onboarding questionnaire (not the PAR-Q), or None."""
    from apps.checkins.models import Form

    qs = Form.objects.filter(type="onboarding", is_parq=False, status="published", client__isnull=True)
    return (qs.filter(name="New client questionnaire").first() or qs.order_by("created_at").first())


def form_questions(form=None):
    """({key: {label, required, help}} for the keyed questions — None when the form has none, so the app asks every
    field —, [extra questions])."""
    form = form if form is not None else questionnaire()
    if form is None:
        return None, []
    live = [q for q in form.questions.all() if not q.is_removed]
    asks = {q.profile_key: {"label": q.text, "required": q.required, "help": q.help_text}
            for q in live if q.profile_key in BY_KEY}
    extra = [{"id": q.id, "text": q.text, "type": q.type, "options": q.options, "scale_labels": q.scale_labels,
              "required": q.required, "help": q.help_text, "allow_other": q.allow_other}
             for q in live if q.profile_key not in BY_KEY and q.type != "photo"]
    return (asks or None), extra


def form_template():
    """The built-in "New client questionnaire": one question per field, in the gym form's words and order."""
    from apps.checkins.defaults import q

    kinds = {"goal": "single", "choice": "single", "other": "single", "gender": "single", "multi": "multiple",
             "text": "short", "long": "long", "int": "number", "num": "number", "date": "short", "phone": "short",
             "yesno": "yes_no", "agree": "yes_no", "measure": "number", "photo": "photo"}
    out = []
    for f in FIELDS:
        opts = [o[1] for o in f.options if o[0] != "none"] if f.kind != "goal" else [g[1] for g in Goal.choices]
        if f.kind in ("photo",):
            opts = [f.label]
        label = f.label if f.kind != "measure" else f"{f.label} (cm)"
        out.append({**q(label, kinds[f.kind], options=opts, help=f.help, required=f.req,
                        other=f.kind == "other"), "profile_key": f.key})
    return out


# ---------------------------------------------------------------- reading values


def _num(v):
    return float(v) if v is not None else None


def raw_value(user, f):
    """The stored answer of one field (API shape)."""
    cp = user.client_profile
    if f.key in USER_ATTRS:
        v = getattr(user, f.key)
        if f.key == "gender":
            return v or ("prefer_not" if (cp.onboarding or {}).get("about", {}).get("gender") == "prefer_not" else "")
        return v.isoformat() if isinstance(v, date) else (v or "")
    if f.kind == "measure":
        body = (cp.onboarding or {}).get("body") or {}
        v = _first_measures(user, body.get("measured_on")).get(f.key[8:])
        return v if v is not None else body.get(f.key)
    if f.kind == "photo":
        return f.key[6:] in start_photos(user)
    if f.kind == "agree":
        return cp.terms_agreed_at is not None
    v = getattr(cp, f.attr or f.key, None)
    if f.kind == "num":
        return _num(v)
    return v


def _first_measures(user, day=None):
    """The measurements taken with the onboarding form (its day), else the first ones logged."""
    from apps.checkins.models import Measurement

    qs = Measurement.objects.filter(client=user)
    m = (qs.filter(date=day).first() if day else None) or qs.order_by("date").first()
    return dict(m.values) if m else {}


def start_photos(user, request=None):
    """{pose: url} of the "Start photos" set (the first set when there is no such label)."""
    from apps.checkins.models import PhotoSet

    sets = PhotoSet.objects.filter(client=user).prefetch_related("photos")
    ps = sets.filter(label="Start photos").order_by("date").first() or sets.order_by("date").first()
    if ps is None:
        return {}
    out = {}
    for p in ps.photos.all():
        url = p.image.url if p.image else ""
        out[p.pose] = request.build_absolute_uri(url) if request and url else url
    return out


def values(user):
    """Every field's stored answer, for the setup steps and Edit profile."""
    return {f.key: raw_value(user, f) for f in FIELDS if f.kind != "photo"}


def _label(options, v):
    return next((o[1] for o in options if o[0] == v), None)


def text(user, key, value=None):
    """One answer as the coach reads it ("—" when empty)."""
    f = BY_KEY[key]
    v = raw_value(user, f) if value is None else value
    if v in (None, "", []):
        return "—"
    if f.kind == "goal":
        return dict(Goal.choices).get(v, v)
    if f.kind in ("choice", "other", "gender"):
        lbl = _label(f.options, v) or (OLD_ACTIVITY.get(v) if key == "activity_level" else None)
        if key == "enrolled_for" and lbl is None and str(v).isdigit():
            lbl = f"{v} months"
        return lbl or str(v)
    if f.kind == "multi":
        picked = [_label(f.options, x) or str(x).replace("_", " ").capitalize() for x in v if x != "none"]
        return ", ".join(picked) if picked else "None"
    if f.kind == "yesno":
        return {True: "Yes", False: "No"}.get(v, "—")
    if f.kind == "photo":
        return "Added" if v else "—"
    if f.kind == "agree":
        return "Agreed" if v else "—"
    if f.kind == "date":
        d = v if isinstance(v, date) else _parse_date(v)
        return d.strftime("%d %b %Y").lstrip("0") if d else str(v)
    if f.kind == "measure":
        return f"{v:g} cm"
    if f.kind == "num":
        if key == "weight_kg" and value is None:  # the form's answer: the weight they started at
            v = ((user.client_profile.onboarding or {}).get("about") or {}).get("weight_kg") or v
        return f"{float(v):g} cm" if key == "height_cm" else f"{float(v):g} kg"
    if f.kind == "phone":
        d = re.sub(r"\D", "", str(v))[-10:]
        return f"+91 {d[:5]} {d[5:]}" if len(d) == 10 else str(v)
    if f.kind == "int" and key == "workout_days":
        return f"{v} day{'s' if v != 1 else ''} a week"
    return str(v)


def _parse_date(v):
    try:
        return date.fromisoformat(str(v)[:10])
    except ValueError:
        return None


def years(dob, today=None):
    if not dob:
        return None
    today = today or timezone.localdate()
    return today.year - dob.year - ((today.month, today.day) < (dob.month, dob.day))


def age(user, today=None):
    """Age today, worked out from the date of birth (never stored, so it never goes stale)."""
    return years(user.date_of_birth, today)


def about_items(user):
    """Overview → "About <name>": what onboarding and Edit profile filled; "—" only when nothing is there."""
    from apps.checkins.models import WeightLog

    cp = user.client_profile
    a = age(user)
    last = WeightLog.objects.filter(client=user).order_by("-date").first()
    now = _num(last.weight_kg) if last else _num(cp.current_weight_kg)

    def kg(v):
        return "—" if v is None else f"{float(v):.1f} kg"

    place = text(user, "workout_place")
    days = cp.workout_days
    trains = " · ".join(x for x in (place if place != "—" else "",
                                    f"{days} days a week" if days else "") if x) or "—"
    level = _label([(k, line) for k, _, line in LEVELS], cp.experience) or "—"
    hurt = [x.strip() for x in (cp.health_notes or "").split("\n") if x.strip()]
    areas = [x for x in (cp.injury_areas or []) if x and x != "none"]
    injuries = hurt[0] if hurt else (text(user, "injury_areas") if areas else ("None" if cp.injury_areas else "—"))
    meds = (cp.medicines_detail.strip().split("\n")[0] if cp.medicines_detail.strip() else "Yes") \
        if cp.takes_medicines else ("None" if cp.takes_medicines is False else "—")
    return [
        {"key": "age", "label": "Age", "value": str(a) if a is not None else "—"},
        {"key": "gender", "label": "Gender", "value": text(user, "gender")},
        {"key": "height", "label": "Height", "value": text(user, "height_cm")},
        {"key": "start_weight", "label": "Start weight", "value": kg(cp.start_weight_kg)},
        {"key": "now", "label": "Now", "value": kg(now)},
        {"key": "goal_weight", "label": "Goal weight", "value": "—" if cp.target_weight_kg is None
         else f"{float(cp.target_weight_kg):g} kg"},
        {"key": "diet", "label": "Diet", "value": text(user, "diet_type")},
        {"key": "trains_at", "label": "Trains at", "value": trains},
        {"key": "experience", "label": "Experience", "value": level},
        {"key": "activity", "label": "Daily activity", "value": text(user, "activity_level")},
        {"key": "workout_time", "label": "Workout time", "value": text(user, "workout_time")},
        {"key": "injuries", "label": "Injuries", "value": injuries, "warn": injuries not in ("None", "—")},
        {"key": "enrolled_for", "label": "Enrolled for", "value": text(user, "enrolled_for")},
        {"key": "medicines", "label": "Medicines", "value": meds, "warn": bool(cp.takes_medicines)},
        {"key": "allergies", "label": "Food allergies", "value": text(user, "food_allergies"),
         "warn": text(user, "food_allergies") not in ("No", "—")},
    ]


def signup_summary(user):
    """Approvals → Review drawer → "From her onboarding": Goal, Body, Trains, Food — only what she filled."""
    cp = user.client_profile
    a = age(user)
    body = " · ".join(x for x in (
        f"{float(cp.current_weight_kg or cp.start_weight_kg):g} kg" if (cp.current_weight_kg or cp.start_weight_kg) else "",
        f"{float(cp.height_cm):g} cm" if cp.height_cm else "",
        f"{a} years" if a is not None else "") if x)
    level = _label([(k, lbl.lower()) for k, lbl, _ in LEVELS], cp.experience) or ""
    place = text(user, "workout_place")
    trains = " · ".join(x for x in (place if place != "—" else "",
                                    f"{cp.workout_days} days a week" if cp.workout_days else "", level) if x)
    goal = dict(Goal.choices).get(cp.goal, "") if cp.goal else ""
    if cp.goal_detail:
        goal = f"{goal} · {cp.goal_detail}" if goal else cp.goal_detail
    food = text(user, "diet_type")
    rows = [("Goal", goal), ("Body", body), ("Trains", trains), ("Food", food if food != "—" else "")]
    return [{"label": k, "value": v} for k, v in rows if v]


def answer_sections(user):
    """Forms → Onboarding questionnaire: every answer by section, in the form's words, then the extra questions."""
    from apps.checkins.models import Question

    asks, extra = form_questions()
    order = []
    rows = {}
    for f in FIELDS:
        if f.kind in ("agree",) or (asks is not None and f.key not in asks):
            continue
        q = (asks or {}).get(f.key, {}).get("label") or f.label
        if f.section not in rows:
            order.append(f.section)
            rows[f.section] = []
        rows[f.section].append({"q": q, "a": text(user, f.key), "key": f.key})
    cp = user.client_profile
    answers = ((cp.onboarding or {}).get("agree") or {}).get("extra") or {}
    if answers:
        texts = dict(Question.objects.filter(id__in=[int(k) for k in answers if str(k).isdigit()])
                     .values_list("id", "text"))
        more = [{"q": texts.get(int(k), "Question"), "a": _extra_text(v), "key": f"q{k}"}
                for k, v in answers.items() if str(k).isdigit()]
        rows.setdefault(LAST, [])
        if LAST not in order:
            order.append(LAST)
        rows[LAST] = more + rows[LAST]
    sections = [{"title": s, "rows": rows[s]} for s in order]
    agreed = cp.terms_agreed_at
    sections.append({"title": TERMS_TITLE, "rows": [{"q": "Agreed to the terms and conditions", "key": "terms",
                                                     "a": timezone.localtime(agreed).strftime("Yes, %d %b %Y")
                                                     .replace(" 0", " ") if agreed else "Not yet"}]})
    return sections


def _extra_text(v):
    if v in (None, "", []):
        return "—"
    if isinstance(v, bool):
        return "Yes" if v else "No"
    if isinstance(v, list):
        return ", ".join(str(x) for x in v)
    return str(v)


# ---------------------------------------------------------------- one setup step


def check_step(step, data, user):
    """(clean answers, errors) for one step. Only the fields the form still asks; required as the form says."""
    asks, extra = form_questions()
    clean, errors = {}, {}
    for f in FIELDS:
        if f.step != step or (asks is not None and f.key not in asks):
            continue
        req = asks[f.key]["required"] if asks is not None else f.req
        v = data.get(f.key)
        if f.kind == "photo":
            pose = f.key[6:]
            have = pose in start_photos(user)
            if v in (None, "", False) and not have:
                if req:
                    errors[f.key] = ["Add this photo."]
                continue
            if isinstance(v, str) and v.startswith("data:"):
                clean[f.key] = v
            continue
        if v in (None, "", []):
            if req:
                errors[f.key] = ["Pick an option." if f.kind in ("goal", "choice", "other", "gender", "multi",
                                                                 "yesno") else "This is required."]
            elif f.kind in ("text", "long", "other", "choice"):
                clean[f.key] = ""  # left empty: cleared on the profile too
            elif f.kind in ("num", "int", "yesno"):
                clean[f.key] = None
            continue
        err = _check(f, v, user)
        if err:
            errors[f.key] = [err]
        else:
            clean[f.key] = _norm(f, v)
    if step == "health":
        if "heart" in (clean.get("conditions") or []) and clean.get("doctor_ok") is not True:
            errors["doctor_ok"] = ["Tick the box once your doctor clears you."]
    if step == "supplements":
        if clean.get("takes_medicines") is True and not clean.get("medicines_detail") \
                and (asks is None or "medicines_detail" in asks):
            errors["medicines_detail"] = ["List your medicines and how long you have taken them."]
        if clean.get("takes_supplements") is True and not clean.get("supplements_detail") \
                and (asks is None or "supplements_detail" in asks):
            errors["supplements_detail"] = ["Tell your coach what you take."]
    if step == "agree":
        given = data.get("extra") or {}
        if not isinstance(given, dict):
            given = {}
        out = {}
        for q in extra:
            v = given.get(str(q["id"]))
            if v in (None, "", []):
                if q["required"]:
                    errors[f"q{q['id']}"] = ["This is required."]
                continue
            if q["type"] == "number":
                try:
                    float(v)
                except (TypeError, ValueError):
                    errors[f"q{q['id']}"] = ["Enter a number."]
                    continue
            out[str(q["id"])] = v if isinstance(v, (bool, int, float, list)) else str(v)[:2000]
        clean["extra"] = out
        if "terms" in clean and clean["terms"] is not True:
            errors["terms"] = ["Tick the box to agree."]
    return clean, errors


def _check(f, v, user):
    k = f.kind
    if k == "goal":
        return None if v in Goal.values else "Pick your main goal."
    if k in ("choice", "gender"):
        return None if v in [o[0] for o in f.options] else "Unknown option."
    if k == "other":
        return None if isinstance(v, str) and len(v.strip()) <= f.max_len else "Keep it short."
    if k == "multi":
        ok = isinstance(v, list) and set(v) <= {o[0] for o in f.options}
        return None if ok else "Unknown option."
    if k in ("text", "long"):
        return None if len(str(v)) <= f.max_len else f"Keep it under {f.max_len} characters."
    if k in ("int", "num", "measure"):
        try:
            n = float(v)
        except (TypeError, ValueError):
            return "Enter a number."
        if k == "int" and n != int(n):
            return "Enter a whole number."
        return None if f.lo <= n <= f.hi else f"Enter a value between {f.lo:g} and {f.hi:g}."
    if k == "date":
        d = _parse_date(v)
        if d is None:
            return "Pick a date."
        return None if 10 <= years(d) <= 100 else "Pick your real date of birth."
    if k == "phone":
        from apps.accounts.models import User

        digits = re.sub(r"\D", "", str(v))
        if len(digits) == 12 and digits.startswith("91"):
            digits = digits[2:]
        if not re.fullmatch(r"[6-9]\d{9}", digits):
            return "Enter a 10-digit mobile number."
        if User.objects.filter(phone=f"+91{digits}").exclude(id=user.id).exists():
            return "Another account uses this number."
        return None
    if k in ("yesno", "agree"):
        return None if isinstance(v, bool) else "Pick Yes or No."
    return None


def _norm(f, v):
    if f.kind == "phone":
        digits = re.sub(r"\D", "", str(v))
        return "+91" + digits[-10:]
    if f.kind == "int":
        return int(float(v))
    if f.kind in ("num", "measure"):
        return round(float(v), 1)
    if f.kind in ("text", "long", "other"):
        return " ".join(str(v).split()) if f.kind != "long" else str(v).strip()
    if f.kind == "multi":
        return ["none"] if "none" in v else list(dict.fromkeys(v))
    if f.kind == "date":
        return _parse_date(v).isoformat()
    return v


def save_step(user, step, clean):
    """Write one checked step into the profile; returns what is kept in `onboarding[step]` (no photo data)."""
    from decimal import Decimal

    from apps.checkins import services as checkins
    from apps.checkins.models import WeightLog

    cp = user.client_profile
    today = timezone.localdate()
    kept = {}
    user_dirty = False
    measures = {}
    for key, v in clean.items():
        if key == "extra":
            kept["extra"] = v
            continue
        f = BY_KEY[key]
        if f.kind == "photo":
            from apps.common.utils import data_url_file

            pose = key[6:]
            checkins.save_photo(user, pose=pose, image=data_url_file(v, pose, field=key), label="Start photos")
            kept.setdefault("photos", []).append(pose)
            continue
        kept[key] = v
        if f.kind == "measure":
            measures[key[8:]] = v
        elif f.kind == "agree":
            cp.terms_agreed_at = cp.terms_agreed_at or timezone.now()
        elif key in USER_ATTRS:
            if v in ("", None):
                continue
            setattr(user, key, "" if (key == "gender" and v == "prefer_not") else
                    (date.fromisoformat(v) if key == "date_of_birth" else v))
            user_dirty = True
        elif v is None and f.kind in ("num", "int", "yesno"):
            setattr(cp, f.attr or key, None)
        elif key == "weight_kg":
            cp.current_weight_kg = Decimal(str(v))
            if cp.start_weight_kg is None or not WeightLog.objects.filter(client=user).exclude(
                    source="onboarding").exists():
                cp.start_weight_kg = Decimal(str(v))
            # The first weigh-in: the day they filled the form (changed again if they edit this step).
            WeightLog.objects.update_or_create(client=user, date=today, defaults={"weight_kg": v,
                                                                                 "source": "onboarding"})
        elif f.kind == "num":
            setattr(cp, f.attr or key, Decimal(str(v)))
        else:
            setattr(cp, f.attr or key, v)
    if measures:
        # The first Measurement: the day they filled this step (the same row again when they edit it).
        day = _parse_date(((cp.onboarding or {}).get("body") or {}).get("measured_on") or "") or today
        checkins.save_measures(user, day, measures)
        kept["measured_on"] = day.isoformat()
    if user_dirty:
        user.save(update_fields=["phone", "date_of_birth", "gender"])
    if step == "health":  # older screens read these from the answers
        kept["injuries"] = clean.get("injury_areas", [])
        kept["notes"] = clean.get("health_notes", "")
    if step == "food":
        kept["diet"] = clean.get("diet_type", "")
    return kept


# ---------------------------------------------------------------- Edit profile


def update_fields():
    """DRF fields for ClientUpdateSerializer: every onboarding field Edit profile can change."""
    out = {}
    for f in EDITABLE:
        k = f.kind
        if k == "choice":
            out[f.key] = serializers.ChoiceField(choices=[o[0] for o in f.options], required=False, allow_blank=True)
        elif k == "other":
            out[f.key] = serializers.CharField(max_length=f.max_len, required=False, allow_blank=True)
        elif k == "multi":
            out[f.key] = serializers.ListField(child=serializers.ChoiceField(choices=[o[0] for o in f.options]),
                                               required=False)
        elif k in ("text", "long"):
            out[f.key] = serializers.CharField(max_length=f.max_len, required=False, allow_blank=True)
        elif k == "int":
            out[f.key] = serializers.IntegerField(min_value=int(f.lo), max_value=int(f.hi), required=False,
                                                  allow_null=True)
        elif k == "yesno":
            out[f.key] = serializers.BooleanField(required=False, allow_null=True)
    return out


def _opts(f):
    if f.kind == "goal":
        return [{"value": k, "label": v} for k, v in Goal.choices]
    return [{"value": o[0], "label": o[1], **({"line": o[2]} if len(o) > 2 else {})} for o in f.options]


def edit_options():
    """Option lists for Edit profile, so the drawer and the app setup read the same words."""
    return {f.key: _opts(f) for f in FIELDS if f.options and f.kind in ("choice", "other", "multi", "gender")}


def setup_fields(asks):
    """What the setup steps ask, in order: every field the admin's form still asks, in its words."""
    out = []
    for f in FIELDS:
        if asks is not None and f.key not in asks:
            continue
        a = (asks or {}).get(f.key) or {}
        label = a.get("label") or f.label
        if f.kind == "measure" and label.endswith(" (cm)"):
            label = label[:-5]
        out.append({"key": f.key, "step": f.step, "kind": f.kind, "label": label,
                    "help": a.get("help", f.help) if asks is not None else f.help,
                    "required": a.get("required", f.req) if asks is not None else f.req,
                    "options": _opts(f), "other": f.other if f.kind == "other" else None,
                    "min": f.lo or None, "max": f.hi or None, "max_len": f.max_len})
    return out


def is_complete(cp):
    return all(k in (cp.onboarding or {}) for k in CLIENT_ONBOARDING_STEPS)
