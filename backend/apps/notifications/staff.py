"""Messages to the team that the trainer switches on in Me → Account → Notifications:
Daily summary (every morning) and Gym news (when the admin posts a notice)."""
from django.contrib.auth import get_user_model
from django.utils import timezone

from .models import Channel, StaffNotificationPreference
from .services import notify

User = get_user_model()
NOTIFY_DEFAULTS = {"daily_summary": False, "gym_news": True}  # Me → Notifications defaults (trainers/me.py)


def wants(user, key):
    tp = getattr(user, "trainer_profile", None)
    if tp is None:
        return False
    return bool({**NOTIFY_DEFAULTS, **(tp.notify or {})}.get(key))


def staff_channels(user, *, email=False):
    """Bell always; push and email follow "Push to your phone and email" (Me → Account)."""
    p = StaffNotificationPreference.objects.filter(user=user).first()
    ch = [Channel.IN_APP]
    if p is None or p.push:
        ch.append(Channel.PUSH)
    if email and (p is None or p.email):
        ch.append(Channel.EMAIL)
    return ch


def team(key):
    """Active staff with a trainer profile who have `key` switched on."""
    qs = (User.objects.filter(role__in=["trainer", "admin"], status="active", is_active=True,
                              trainer_profile__isnull=False)
          .select_related("trainer_profile"))
    return [u for u in qs if wants(u, key)]


def _n(n, one, many=None):
    return f"{n or 'no'} {one if n == 1 else (many or one + 's')}"


def daily_summary_counts(user, now=None):
    """The dashboard's own numbers: today's sessions, the check-in queue, Clients who need you."""
    from apps.activity.trainer_home import checkins_to_review, clients_who_need_you, today_sessions

    now = now or timezone.now()
    waiting, _ = checkins_to_review(user, now)
    return {"sessions": today_sessions(user, now), "checkins": len(waiting), "need": len(clients_who_need_you(user, now))}


def daily_summary_text(c):
    s = c["sessions"]
    title = (f"Today: {_n(len(s), 'session')}, {_n(c['checkins'], 'check-in')} to review, "
             f"{_n(c['need'], 'client needs', 'clients need')} you")
    nxt = next((x for x in s if x["status"] == "booked"), None)
    body = f"First session {nxt['time']} with {nxt['client']['name']}." if nxt else "No sessions booked today."
    if c["checkins"] == 0 and c["need"] == 0:
        body += " Nothing waiting for you."
    return title, body + " Tap to open your Dashboard."


def send_daily_summary(user, now=None):
    title, body = daily_summary_text(daily_summary_counts(user, now))
    return notify(user, "daily_summary", title, body, data={"route": "/dashboard"},
                  channels=staff_channels(user, email=True), email_subject="Your day at Train With Vimal")


def send_gym_news(news):
    people = [u for u in team("gym_news") if u.id != news.author_id]
    for u in people:
        notify(u, "gym_news", news.title, news.body, data={"route": "/dashboard", "gym_news": str(news.id)},
               channels=staff_channels(u), actor=news.author)
    news.sent_to = len(people)
    news.save(update_fields=["sent_to", "updated_at"])
    return people
