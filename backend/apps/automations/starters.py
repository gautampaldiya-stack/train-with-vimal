"""New automation → starter list. Forms are looked up by name when a starter is used."""

TRIGGER_TEXT = {
    "client_approved": "As soon as they are approved.",
    "plan_starts": "A program or meal plan starts.",
    "plan_ends": "Before a plan ends.",
    "package_ending": "Before a package ends.",
    "birthday": "On the client's birthday.",
    "every_week": "Same day and time each week.",
    "every_day": "Same time every day.",
    "on_date": "Once, on a date you pick.",
    "missed_checkin": "A check-in is late.",
    "missed_workouts": "Workouts missed in a row.",
    "no_activity": "The app is not opened.",
    "form_sent": "A client sends a form.",
    "workout_streak": "Workouts done days in a row.",
    "goal_weight": "Weight reaches the goal.",
    "weight_flat": "Weight stays the same.",
}

# Settings each trigger needs, with limits (the builder shows only these).
TRIGGER_CONFIG = {
    "plan_ends": {"days_before": (0, 14, 3), "plan_type": ["any", "program", "meal_plan"]},
    "plan_starts": {"plan_type": ["any", "program", "meal_plan"]},
    "package_ending": {"days_before": (1, 30, 7)},
    "birthday": {"time": "09:00"},
    "every_week": {"weekday": (0, 6, 6), "time": "09:00"},
    "every_day": {"time": "08:00"},
    "on_date": {"date": None, "time": "09:00"},
    "missed_checkin": {"hours": (6, 72, 24)},
    "missed_workouts": {"count": (1, 10, 2)},
    "no_activity": {"days": (2, 30, 7)},
    "form_sent": {"form": None},
    "workout_streak": {"days": (3, 60, 7)},
    "weight_flat": {"weeks": (1, 8, 3)},
}


def _msg(template, channels):
    return {"kind": "message", "config": {"template": template, "channels": channels}}


def _form(form_name, channels):
    return {"kind": "form", "config": {"form_name": form_name, "channels": channels}}


def _wait(days=0, hours=0):
    return {"kind": "wait", "config": {"days": days, "hours": hours}}


def _task(title, assignee="trainer", due_days=1):
    return {"kind": "task", "config": {"title": title, "assignee": assignee, "due_days": due_days}}


STARTERS = [
    {"key": "client_onboarding", "name": "Client onboarding",
     "line": "Sends the onboarding form on approval, reminds on WhatsApp, then asks the trainer to call.",
     "trigger": "client_approved", "trigger_config": {}, "stop_on_response": True,
     "steps": [_form("New client questionnaire", ["push", "email"]), _wait(days=1),
               _msg("onboarding-form-reminder", ["whatsapp", "push"]), _wait(days=2),
               _task("Call the client")]},
    {"key": "weekly_checkin", "name": "Weekly check-in",
     "line": "Sends the check-in every Sunday, reminds after 24 hours, then gives the trainer a review task.",
     "trigger": "every_week", "trigger_config": {"weekday": 6, "time": "09:00"}, "stop_on_response": True,
     "steps": [_form("Weekly check-in", ["push", "in_app"]), _wait(hours=24),
               _msg("checkin-reminder", ["push", "whatsapp"]), _wait(days=1),
               _task("Review the weekly check-in")]},
    {"key": "missed_checkin", "name": "Missed check-in reminder",
     "line": "A short reminder flow that works with any check-in.",
     "trigger": "missed_checkin", "trigger_config": {"hours": 24}, "stop_on_response": True,
     "steps": [_msg("checkin-reminder", ["push"]), _wait(days=1), _task("Check in with the client")]},
    {"key": "missed_workouts", "name": "Missed workouts nudge",
     "line": "A friendly nudge first, then the trainer checks in.",
     "trigger": "missed_workouts", "trigger_config": {"count": 2}, "stop_on_response": True,
     "steps": [_msg("missed-workouts-nudge", ["push"]), _wait(days=2), _task("Call the client")]},
    {"key": "renewal", "name": "Renewal reminder",
     "line": "Two reminders before the package ends, then a call from the trainer.",
     "trigger": "package_ending", "trigger_config": {"days_before": 7}, "stop_on_response": False,
     "steps": [_msg("renewal-reminder", ["email", "push"]), _wait(days=4),
               _msg("renewal-reminder", ["whatsapp"]), _wait(days=1), _task("Talk about renewal")]},
    {"key": "welcome_week", "name": "Welcome week",
     "line": "A welcome message, the health screening on day 2 and a first-week call.",
     "trigger": "client_approved", "trigger_config": {}, "stop_on_response": False,
     "steps": [_msg("welcome", ["push", "email"]), _wait(days=1),
               _form("PAR-Q health screening", ["push"]), _wait(days=4), _task("First-week call")]},
    {"key": "birthday", "name": "Birthday wish",
     "line": "A birthday message at 9 am and a reminder for the trainer.",
     "trigger": "birthday", "trigger_config": {"time": "09:00"}, "stop_on_response": False,
     "steps": [_msg("birthday-wish", ["push", "in_app"]), _task("Wish the client a happy birthday",
                                                                 due_days=0)]},
]
