"""Trainer permission keys (Trainer profile → Access and permissions)."""

GROUPS = [
    ("Clients", [
        ("clients.view_assigned", "View assigned clients", ""),
        ("clients.view_all", "View all clients", ""),
        ("clients.approve_signups", "Approve sign-ups", "Only people invited by him"),
        ("clients.pause", "Pause or resume clients", ""),
    ]),
    ("Training", [
        ("training.programs_edit", "Create and edit programs", "For his clients"),
        ("training.use_templates", "Use gym templates", "Copy master programs"),
        ("training.edit_templates", "Edit gym templates", "Changes master programs"),
        ("training.custom_exercises", "Add custom exercises", ""),
    ]),
    ("Nutrition", [
        ("nutrition.meal_plans", "Meal plans", ""),
        ("nutrition.foods", "Add foods and recipes", ""),
        ("nutrition.supplements", "Supplement plans", ""),
        ("nutrition.food_logs", "See food logs", ""),
    ]),
    ("Check-ins", [
        ("checkins.daily", "Review daily check-ins", ""),
        ("checkins.weekly", "Review weekly check-ins", ""),
        ("checkins.edit_forms", "Edit check-in forms", "Changes master forms"),
        ("checkins.photos", "Progress photos", ""),
    ]),
    ("Schedule", [
        ("schedule.own_calendar", "Manage own calendar", ""),
        ("schedule.book_sessions", "Book sessions for clients", ""),
    ]),
    ("Content", [
        ("content.manage", "Manage content library", ""),
    ]),
]

ALL_KEYS = [k for _, items in GROUPS for k, _, _ in items]

ASSIGNED_PRESET = {
    "clients.view_assigned": True, "clients.view_all": False, "clients.approve_signups": False,
    "clients.pause": False,
    "training.programs_edit": True, "training.use_templates": True, "training.edit_templates": False,
    "training.custom_exercises": True,
    "nutrition.meal_plans": True, "nutrition.foods": True, "nutrition.supplements": True,
    "nutrition.food_logs": True,
    "checkins.daily": True, "checkins.weekly": True, "checkins.edit_forms": False, "checkins.photos": True,
    "schedule.own_calendar": True, "schedule.book_sessions": True,
    "content.manage": True,
}

ALL_CLIENTS_PRESET = {**ASSIGNED_PRESET, "clients.view_all": True, "clients.pause": True,
                      "clients.approve_signups": True}

# Role matrix (Settings) columns that cap or widen trainer permissions for everyone.
MATRIX_CEILING = {
    "training.programs_edit": "create_plans",
    "nutrition.meal_plans": "create_plans",
    "checkins.daily": "checkins",
    "checkins.weekly": "checkins",
    "content.manage": "manage_content",
    "schedule.book_sessions": "schedule_sessions",
}
MATRIX_GRANT = {"clients.view_all": "view_all_clients"}

# Fields on "What clients see" (Trainer profile tab), default on/off.
VISIBILITY_DEFAULTS = {
    "photo_name": True,  # locked, always on
    "speciality": True,
    "experience": True,
    "about": True,
    "languages": True,
    "certificates": True,
    "social": True,
    "mobile": False,
    "email": False,
}
