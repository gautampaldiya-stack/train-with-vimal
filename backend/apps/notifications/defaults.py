"""Built-in message templates and team alerts (seeded by `manage.py seed_defaults`)."""


def _ch(email=None, push=None, whatsapp=None, in_app=None):
    def one(v, with_subject=False):
        if v is None:
            return {"on": False, "subject": "", "title": "", "body": ""}
        title, body = v
        return {"on": True, "subject": title if with_subject else "", "title": "" if with_subject else title,
                "body": body}

    return {"email": one(email, True), "push": one(push), "whatsapp": one(whatsapp), "in_app": one(in_app)}


TEMPLATES = [
    ("client-invite", "Client invite", "access", _ch(
        email=("You're invited to {{gym_name}}",
               "Hi {{first_name}},\n\n{{coach_name}} invited you to {{gym_name}}. Open the link to set your password and get started."),
        whatsapp=(None, "Hi {{first_name}}, {{coach_name}} invited you to {{gym_name}}. Open your link to get started."),
    )),
    ("welcome", "Welcome", "access", _ch(
        email=("Welcome to {{gym_name}}", "Hi {{first_name}},\n\nYour account is ready. {{coach_name}} is your coach."),
        push=("Welcome, {{first_name}}", "Your account is ready. Let's set up your profile."),
        in_app=("Welcome to {{gym_name}}", "Your account is approved. {{coach_name}} is your coach."),
    )),
    ("password-reset", "Password reset", "access", _ch(
        email=("Reset your password", "Hi {{first_name}},\n\nUse the link below to set a new password. It works for 2 hours."),
    )),
    ("onboarding-form-reminder", "Onboarding form reminder", "coaching", _ch(
        push=("Finish your setup", "{{coach_name}} can't build your plan until setup is done."),
        email=("Finish your profile setup", "Hi {{first_name}},\n\n{{coach_name}} needs a few more details to build your plan."),
        in_app=("Finish your setup", "A few steps are left in your profile setup."),
    )),
    ("checkin-reminder", "Check-in reminder", "coaching", _ch(
        push=("Your check-in is due", "Send your weekly check-in so {{coach_name}} can review your week."),
        in_app=("Your check-in is due", "Send your weekly check-in today."),
        email=("Your weekly check-in is due", "Hi {{first_name}},\n\nYour weekly check-in is due today."),
    )),
    ("missed-workouts-nudge", "Missed workouts nudge", "coaching", _ch(
        push=("We miss you, {{first_name}}", "A short session today keeps your streak going."),
        in_app=("Missed workouts", "You missed a few workouts. A short one today helps."),
    )),
    ("coach-feedback", "Coach feedback", "coaching", _ch(
        push=("{{coach_name}} replied", "Open your check-in to read the reply."),
        in_app=("{{coach_name}} replied to your check-in", "Open it to read the reply."),
    )),
    ("birthday-wish", "Birthday wish", "coaching", _ch(
        push=("Happy birthday, {{first_name}}!", "Wishing you a strong year ahead from {{gym_name}}."),
        in_app=("Happy birthday!", "Wishing you a strong year ahead from {{gym_name}}."),
    )),
    ("renewal-reminder", "Renewal reminder", "packages", _ch(
        email=("Your {{package_name}} ends soon", "Hi {{first_name}},\n\nYour {{package_name}} ends on {{date}}. Talk to {{coach_name}} about what's next."),
        push=("Your package ends soon", "{{package_name}} ends on {{date}}."),
    )),
    ("trainer-invite", "Trainer invite", "access", _ch(
        email=("Join the {{gym_name}} team", "Hi {{first_name}},\n\nYou were added as a trainer at {{gym_name}}. Open the link to set your password."),
    )),
]

TEAM_ALERTS = {
    "new_client": {"email": True, "push": True, "whatsapp": False, "in_app": True},
    "checkin_submitted": {"email": False, "push": True, "whatsapp": False, "in_app": True},
    "plan_updated": {"email": False, "push": False, "whatsapp": False, "in_app": True},
    "missed_workout": {"email": False, "push": True, "whatsapp": False, "in_app": True},
}


def default_channels_for(key):
    for k, _n, _g, ch in TEMPLATES:
        if k == key:
            return ch
    return None


def seed():
    from .models import MessageTemplate, NotificationSettings, TeamAlertSetting

    for key, name, group, channels in TEMPLATES:
        MessageTemplate.objects.get_or_create(
            key=key, defaults={"name": name, "group": group, "channels": channels, "default_channels": channels}
        )
    for event, channels in TEAM_ALERTS.items():
        TeamAlertSetting.objects.get_or_create(event=event, defaults={"channels": channels})
    NotificationSettings.load()
