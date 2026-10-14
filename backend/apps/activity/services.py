from django.db import transaction

from apps.common.middleware import client_source, get_current_request

from .models import ActivityEvent, ActorType


def _source(actor):
    req = get_current_request()
    if actor is None:
        return "System"
    role = actor.get_role_display() if hasattr(actor, "get_role_display") else ""
    return f"{role} · {client_source(req)}"


def log(
    verb,
    kind,
    *,
    actor=None,
    actor_type=None,
    actor_label=None,
    target=None,
    target_label="",
    change=None,
    client=None,
    trainer=None,
    source=None,
    meta=None,
):
    """Record one row on the timeline. Written after the surrounding transaction commits,
    so a rolled-back change never shows up in the log."""
    if actor_type is None:
        if actor is None:
            actor_type = ActorType.SYSTEM
        elif getattr(actor, "is_client", False):
            actor_type = ActorType.CLIENT
        else:
            actor_type = ActorType.TEAM
    if trainer is None and client is not None:
        profile = getattr(client, "client_profile", None)
        trainer = getattr(profile, "trainer", None) if profile else None
    data = dict(
        actor=actor,
        actor_type=actor_type,
        actor_label=actor_label or (actor.full_name if actor else "System"),
        source=source or _source(actor),
        kind=kind,
        verb=verb[:200],
        target_type=target.__class__.__name__ if target is not None else "",
        target_id=str(getattr(target, "pk", "") or ""),
        target_label=(target_label or (str(target) if target is not None else ""))[:200],
        change_from=str(change[0])[:120] if change else "",
        change_to=str(change[1])[:120] if change else "",
        client=client,
        trainer=trainer,
        meta=meta or {},
    )
    transaction.on_commit(lambda: ActivityEvent.objects.create(**data))
