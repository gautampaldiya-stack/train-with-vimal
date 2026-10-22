import random
import re

from django.contrib.auth import get_user_model
from django.db import transaction
from django.db.models import Count, Q
from django.utils import timezone

from apps.accounts.models import AccountStatus, OneTimeToken, Role
from apps.accounts.tokens import issue_one_time_token
from apps.activity.services import log as activity_log
from apps.notifications.services import notify

from .models import Approval, ClientProfile, InviteLink, SignupSource

User = get_user_model()


# ---------------------------------------------------------------- scoping
def can_see_all_clients(user):
    if user.is_admin:
        return True
    return user.is_trainer and user.trainer_profile.has_perm("clients.view_all")


def visible_clients(user):
    """Clients this person may see. Every client-related view starts from here, so a
    trainer asking for someone else's client gets a plain 404."""
    qs = User.objects.filter(role=Role.CLIENT, client_profile__removed_at__isnull=True)
    if user.is_client:
        return qs.filter(id=user.id)
    if can_see_all_clients(user):
        return qs
    return qs.filter(client_profile__trainer=user)


def get_visible_client(user, client_id):
    return visible_clients(user).select_related("client_profile", "client_profile__trainer").get(id=client_id)


def trainer_load(trainers_qs=None):
    """{trainer_id: active client count} in one query."""
    qs = User.objects.filter(role__in=[Role.TRAINER, Role.ADMIN], trainer_profile__isnull=False)
    if trainers_qs is not None:
        qs = trainers_qs
    rows = qs.annotate(
        n=Count("coached_clients", filter=Q(coached_clients__user__status=AccountStatus.ACTIVE,
                                            coached_clients__removed_at__isnull=True))
    ).values_list("id", "n")
    return dict(rows)


# ---------------------------------------------------------------- create
@transaction.atomic
def create_client(*, actor, full_name, phone=None, email=None, trainer=None, send_to_approvals=False,
                  send_login_link=True, ask_parq=True, source=SignupSource.ADDED, password=None,
                  invite_link=None, invited_by=None, **profile):
    status = AccountStatus.PENDING if send_to_approvals else AccountStatus.ACTIVE
    user = User.objects.create_user(
        email=email or None, phone=phone or None, password=password, full_name=full_name, role=Role.CLIENT,
        status=status, gender=profile.pop("gender", ""), date_of_birth=profile.pop("date_of_birth", None),
        city=profile.pop("city", ""),
    )
    start_weight = profile.pop("current_weight_kg", None)
    cp = ClientProfile.objects.create(
        user=user, trainer=trainer, trainer_since=timezone.now() if trainer else None, ask_parq=ask_parq, signup_source=source, invite_link=invite_link,
        invited_by=invited_by or actor, start_weight_kg=start_weight, current_weight_kg=start_weight,
        onboarding_done=["account"] if (email or phone) else [], **profile,
    )
    if send_to_approvals:
        Approval.objects.create(client=user, invited_by=invited_by or actor or (trainer if trainer else None),
                                signed_up_from=source)
        notify_approvers(user, trainer)
    elif send_login_link and email:
        from apps.accounts.emails import send_login_link as email_login_link

        token = issue_one_time_token(user, OneTimeToken.Purpose.LOGIN_LINK)
        email_login_link(user, token)
    if actor:
        activity_log("added a client", "client", actor=actor, target=user, target_label=user.full_name, client=user,
                     trainer=trainer)
    if actor and not send_to_approvals:
        from apps.notifications.staff import team_alert

        team_alert("new_client", user, f"{user.full_name} is your client now", "Open their profile to plan what is next.",
                   notify_event="client_assigned", actor=actor, trainer=trainer, pref="new_client",
                   owner_title=f"New client: {user.full_name}", data={"route": f"/clients/{user.id}"})
    return user, cp


def notify_approvers(user, trainer):
    admins = list(User.objects.filter(role=Role.ADMIN))
    targets = set(admins)
    if trainer and trainer.is_trainer and trainer.trainer_profile.has_perm("clients.approve_signups"):
        targets.add(trainer)
    notify(list(targets), "approval_waiting", f"{user.full_name} is waiting for approval",
           "New sign-up from an invite link.", data={"route": "/approvals", "client": str(user.id)})


# ---------------------------------------------------------------- invite links
def make_link_code(trainer):
    base = re.sub(r"[^A-Z]", "", (trainer.first_name or "TWV").upper())[:6] or "TWV"
    for _ in range(20):
        code = f"{base}-{random.randint(1000, 9999)}"
        if not InviteLink.all_objects.filter(code=code).exists():
            return code
    return f"{base}-{random.randint(10000, 99999)}"


# ---------------------------------------------------------------- approvals
@transaction.atomic
def approve(approval, *, actor, trainer, tell_client=True, ask_finish_setup=True):
    user = approval.client
    user.status = AccountStatus.ACTIVE
    user.save(update_fields=["status"])
    cp = user.client_profile
    cp.trainer = trainer
    cp.trainer_since = timezone.now()
    cp.save(update_fields=["trainer", "trainer_since", "updated_at"])
    approval.status = Approval.Status.APPROVED
    approval.decided_by = actor
    approval.decided_at = timezone.now()
    approval.assigned_trainer = trainer
    approval.moved_back = False
    approval.save()
    activity_log("approved a sign-up", "client", actor=actor, target=user, target_label=user.full_name, client=user,
                 trainer=trainer)
    if tell_client:
        from apps.notifications.services import send_template

        send_template(user, "welcome", actor=actor, urgent=True)
    if ask_finish_setup and len(cp.onboarding_done or []) < 5:
        from apps.notifications.services import send_template

        send_template(user, "onboarding-form-reminder", actor=actor)
    from apps.notifications.staff import team_alert

    team_alert("new_client", user, f"{user.full_name} is your client now", "Approved from the sign-up list.",
               notify_event="client_assigned", actor=actor, trainer=trainer, pref="new_client",
               owner_title=f"New client: {user.full_name}", data={"route": f"/clients/{user.id}"})
    from apps.automations.engine import fire_event

    fire_event("client_approved", user)
    return approval


@transaction.atomic
def reject(approval, *, actor, reason, message="", tell_client=True):
    user = approval.client
    user.status = AccountStatus.REJECTED
    user.save(update_fields=["status"])
    approval.status = Approval.Status.REJECTED
    approval.reject_reason = reason
    approval.message = message
    approval.decided_by = actor
    approval.decided_at = timezone.now()
    approval.save()
    activity_log("rejected a sign-up", "client", actor=actor, target=user, target_label=user.full_name, client=user,
                 meta={"reason": reason})
    if tell_client and user.email:
        from apps.accounts.emails import _queue

        reason_label = Approval.RejectReason(reason).label
        _queue(user.email, "About your sign-up", f"Hi {user.first_name},\n\n{message or reason_label}")


@transaction.atomic
def move_back(approval, *, actor, tell_client=False):
    user = approval.client
    user.status = AccountStatus.PENDING
    user.save(update_fields=["status"])
    approval.status = Approval.Status.WAITING
    approval.moved_back = True
    approval.decided_at = None
    approval.save()
    activity_log("moved a sign-up back to Waiting", "client", actor=actor, target=user, target_label=user.full_name,
                 client=user)
    if tell_client:
        notify(user, "approval_review", "Your account is being looked at again",
               "We will let you know when it is approved.", channels=["in_app", "email"])
