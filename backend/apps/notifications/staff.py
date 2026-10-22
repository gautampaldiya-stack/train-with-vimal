"""Messages to the team that the trainer switches on in Me → Account → Notifications:
Daily summary (every morning) and Gym news (when the admin posts a notice)."""
from django.contrib.auth import get_user_model
from django.utils import timezone

from apps.common.utils import dfmt

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


# ---------------------------------------------------------------- Emails & alerts → Team alerts
def team_alert_channels(event):
    """The channels the owner ticked for this team alert (board Team alerts table)."""
    from .defaults import TEAM_ALERTS
    from .models import TeamAlertSetting

    row = TeamAlertSetting.objects.filter(event=event).first()
    chosen = row.channels if row else TEAM_ALERTS.get(event, {})
    return [c for c in (Channel.IN_APP, Channel.PUSH, Channel.EMAIL, Channel.WHATSAPP) if chosen.get(c)]


def team_alert(event, client, title, body="", *, notify_event, actor=None, data=None, pref=None, owner_title=None,
               trainer=None):
    """Goes to you and the assigned trainer (never to the person who did it), on the ticked channels.
    Each person's own switches still count: `pref` (Me → Notifications, e.g. new_checkin) and Push / Email."""
    chans = team_alert_channels(event)
    if not chans:
        return []
    if trainer is None:
        cp = getattr(client, "client_profile", None)
        trainer = getattr(cp, "trainer", None) if cp else None
    owners = list(User.objects.filter(role="admin", is_active=True))
    people = []
    for u in ([trainer] if trainer else []) + owners:
        if u is None or u in people or (actor is not None and u.id == actor.id):
            continue
        people.append(u)
    sent = []
    for u in people:
        p = StaffNotificationPreference.objects.filter(user=u).first()
        if pref and p is not None and not getattr(p, pref):
            continue
        ch = [c for c in chans if not (p is not None and ((c == Channel.PUSH and not p.push)
                                                           or (c == Channel.EMAIL and not p.email)))]
        if not ch:
            continue
        mine = trainer is not None and u.id == trainer.id
        sent += notify(u, notify_event, title if mine else (owner_title or title), body, data=data, actor=actor,
                       channels=ch, in_app=Channel.IN_APP in ch)
    return sent


# ---------------------------------------------------------------- Emails & alerts → Daily digest
def digest_counts(user, now=None):
    """What the digest email lists for one person: their check-ins to review, at-risk clients, plans ending."""
    from datetime import timedelta

    from apps.checkins.queue import review_queue
    from apps.clients.services import visible_clients
    from apps.training.models import AssignmentStatus, ProgramAssignment

    today = timezone.localdate(now)
    mine = visible_clients(user).filter(status="active")
    ending = (ProgramAssignment.objects.filter(client__in=mine, status=AssignmentStatus.ACTIVE,
                                               end_date__range=(today, today + timedelta(days=7)))
              .select_related("client", "program").order_by("end_date"))
    return {
        "checkins": review_queue(user).count(),
        "at_risk": list(mine.filter(client_profile__at_risk=True).select_related("client_profile")[:10]),
        "ending": list(ending[:10]),
    }


def digest_text(c, weekly=False):
    lines = [f"Check-ins to review: {c['checkins']}"]
    lines.append(f"\nAt-risk clients: {len(c['at_risk'])}")
    lines += [f"• {u.full_name}: {u.client_profile.at_risk_reason or 'needs a check'}" for u in c["at_risk"]]
    lines.append(f"\nPlans ending in the next 7 days: {len(c['ending'])}")
    lines += [f"• {a.client.full_name}: {a.program.name} ends {dfmt(a.end_date, '%-d %b')}" for a in c["ending"]]
    title = "Your weekly digest" if weekly else "Your daily digest"
    return title, "\n".join(lines)


def send_digests(now=None, first=None):
    """8:00 am: the digest email to you and each active trainer. Weekly = Mondays only. Off = nothing."""
    from .models import NotificationSettings

    now = timezone.localtime(now)
    mode = NotificationSettings.load().digest
    if mode == "off" or (mode == "weekly" and now.weekday() != 0):
        return []
    sent = []
    for u in User.objects.filter(role__in=["admin", "trainer"], status="active", is_active=True):
        p = StaffNotificationPreference.objects.filter(user=u).first()
        if (p is not None and not p.email) or (first is not None and not first(u)):
            continue
        title, body = digest_text(digest_counts(u, now), weekly=mode == "weekly")
        sent += notify(u, "digest", title, body, channels=[Channel.EMAIL], in_app=False,
                       email_subject=f"{title} · {dfmt(now, '%-d %b')}")
    return sent
