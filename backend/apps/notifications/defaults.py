"""Built-in message templates and team alerts (seeded by `manage.py seed_defaults`)."""


def _ch(email=None, push=None, whatsapp=None, in_app=None):
    def one(v, with_subject=False):
        if v is None:
            return {"on": False, "subject": "", "title": "", "body": ""}
        title, body = v
        return {"on": True, "subject": title if with_subject else "", "title": "" if with_subject else title,
                "body": body}

    return {"email": one(email, True), "push": one(push), "whatsapp": one(whatsapp), "in_app": one(in_app)}


# Board Emails: the words of every built-in message, per channel (title / subject, text).
TEMPLATES = [
    ("client-invite", "Client invite", "access", _ch(
        email=("{{coach_name}} invited you to {{gym_name}}",
               "Hi {{first_name}},\n\n{{coach_name}} has invited you to {{gym_name}}. Create your account to see your "
               "plan: {{package_name}}.\n\nThe invite is valid until {{date}}."),
        whatsapp=("", "Hi {{first_name}}, {{coach_name}} has invited you to {{gym_name}}. Open the invite to create "
                      "your account. It is valid until {{date}}."),
    )),
    ("welcome", "Welcome", "access", _ch(
        email=("You are in! Your {{gym_name}} account is active",
               "Hi {{first_name}},\n\nYour account is approved and Coach {{coach_name}} has your plan ready.\n\n"
               "Open the app to see your first workout."),
        push=("Welcome aboard, {{first_name}}", "Your account is active. Say hi to Coach {{coach_name}}."),
        whatsapp=("", "Hi {{first_name}}, your {{gym_name}} account is active. Coach {{coach_name}} has your plan "
                      "ready. Open the app to see your first workout."),
        in_app=("Welcome aboard, {{first_name}}", "Coach {{coach_name}} has your plan ready. Start with your first workout."),
    )),
    ("password-reset", "Password reset", "access", _ch(
        email=("Reset your {{gym_name}} password",
               "Hi {{first_name}},\n\nUse the link in this email to set a new password. It works for 15 minutes.\n\n"
               "If you did not ask for this, you can ignore this email."),
    )),
    ("onboarding-form-reminder", "Onboarding form reminder", "coaching", _ch(
        email=("Your onboarding form is waiting",
               "Hi {{first_name}},\n\nCoach {{coach_name}} needs your onboarding form to finish your plan. It takes "
               "about 5 minutes."),
        push=("Finish your onboarding form", "Coach {{coach_name}} needs it to build your plan. About 5 minutes."),
        whatsapp=("", "Hi {{first_name}}, a quick reminder: Coach {{coach_name}} needs your onboarding form to finish "
                      "your plan. It takes about 5 minutes."),
    )),
    ("checkin-reminder", "Check-in reminder", "coaching", _ch(
        email=("Weekly check-in time, {{first_name}}",
               "Hi {{first_name}},\n\nIt takes 2 minutes: your weight, measurements and how the week went. Coach "
               "{{coach_name}} replies with feedback."),
        push=("Check-in time", "Your weekly check-in is due today. It takes 2 minutes."),
        whatsapp=("", "Good morning {{first_name}}. Your weekly check-in is due today. Coach {{coach_name}} is "
                      "waiting for it."),
        in_app=("Check-in time", "Share your weight and how the week went. It takes 2 minutes."),
    )),
    ("missed-workouts-nudge", "Missed workouts nudge", "coaching", _ch(
        push=("All good, {{first_name}}?", "A 20-minute workout is ready whenever you are."),
        whatsapp=("", "Hi {{first_name}}, we noticed a few missed workouts. All good? A short 20-minute session is "
                      "ready when you are."),
        in_app=("Ease back in", "A 20-minute workout is ready. Start small today."),
    )),
    ("coach-feedback", "Coach feedback", "coaching", _ch(
        push=("Coach {{coach_name}} replied", "Your check-in feedback is ready."),
        in_app=("Coach {{coach_name}} replied", "Read the feedback on your latest check-in."),
    )),
    ("birthday-wish", "Birthday wish", "coaching", _ch(
        push=("Happy birthday, {{first_name}}", "Have a great day. Wishes from Coach {{coach_name}} and the team."),
        whatsapp=("", "Happy birthday, {{first_name}}! Wishing you a strong and healthy year. Coach {{coach_name}} "
                      "and the {{gym_name}} team."),
    )),
    ("renewal-reminder", "Renewal reminder", "packages", _ch(
        email=("Your {{package_name}} ends on {{date}}",
               "Hi {{first_name}},\n\nYour {{package_name}} ends on {{date}}. Renew to keep training with Coach "
               "{{coach_name}}."),
        push=("Your plan ends soon", "{{package_name}} ends on {{date}}. Renew to keep going."),
        whatsapp=("", "Hi {{first_name}}, your {{package_name}} ends on {{date}}. Renew to keep training with Coach "
                      "{{coach_name}}."),
    )),
    ("trainer-invite", "Trainer invite", "team", _ch(
        email=("Join {{gym_name}} as a trainer",
               "Hi {{first_name}},\n\nYou have been invited to join {{gym_name}} as a trainer. Set up your profile in "
               "about 3 minutes. The invite is valid until {{date}}."),
    )),
]

# "Sent: ..." under each message's name (board Emails list and editor head).
WHEN = {
    "client-invite": "When you send an invite to a client",
    "welcome": "When a client is approved",
    "password-reset": "When someone asks to reset their password",
    "onboarding-form-reminder": "When the onboarding form is still open",
    "checkin-reminder": "When a check-in is due or was missed",
    "missed-workouts-nudge": "When workouts are missed in a row",
    "coach-feedback": "When the coach replies to a check-in",
    "birthday-wish": "On the client\u2019s birthday",
    "renewal-reminder": "Before a package ends",
    "trainer-invite": "When you invite a trainer",
}
CUSTOM_WHEN = "By an automation you pick"

# "Where it is used" for messages the app itself sends (no automation step needed).
SENT_BY = {
    "client-invite": "Sent by the app when you invite a client from Clients or Approvals",
    "welcome": "Sent by the app when you approve someone in Approvals",
    "password-reset": "Sent by the app on Forgot password",
    "coach-feedback": "Sent by the app when a trainer replies to a check-in",
    "trainer-invite": "Sent by the app when you add a trainer",
    "onboarding-form-reminder": "Sent by the app while a new client's setup is open",
    "checkin-reminder": "Sent by the app on the day a check-in is due",
}

TEAM_ALERTS = {
    "new_client": {"email": True, "push": True, "whatsapp": False, "in_app": True},
    "checkin_submitted": {"email": False, "push": True, "whatsapp": False, "in_app": True},
    "plan_updated": {"email": False, "push": False, "whatsapp": False, "in_app": True},
    "missed_workout": {"email": False, "push": True, "whatsapp": True, "in_app": True},
}
TEAM_ALERT_NOTES = {
    "new_client": "Sign-up or invite accepted",
    "checkin_submitted": "Weekly check-in by a client",
    "plan_updated": "Trainer edits a program or meal plan",
    "missed_workout": "2+ workouts skipped in a row",
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
