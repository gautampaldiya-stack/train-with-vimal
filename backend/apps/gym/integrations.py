"""Settings → Integrations (D-53): the three cards, their "Used in" links, and the email domain DNS check.

Provider keys (Meta token, SMTP) stay in .env. These rows decide whether the app uses the service:
- WhatsApp off → WhatsApp messages are skipped (email, push and in-app keep going).
- Email domain verified → emails come from hello@<domain>; until then from the platform address.
- Health → which data types clients may share once the phone apps read them.
"""
import logging

import httpx
from django.utils import timezone

from .models import Integration

log = logging.getLogger("notifications")

NAMES = {"whatsapp": "WhatsApp Business", "email_domain": "Email sending", "health": "Apple Health / Health Connect"}

# (label, TXT host under the domain, what the record must start with)
DNS_RECORDS = [("SPF", "@", "v=spf1"), ("DKIM", "twv._domainkey", "v=dkim1"), ("DMARC", "_dmarc", "v=dmarc1")]


def _used():
    """The "Used in" links of each card, counted from what is set up now."""
    from apps.automations.models import Automation
    from apps.notifications.models import MessageTemplate, TemplateGroup

    wa_autos = 0
    for a in Automation.objects.prefetch_related("steps"):
        if any("whatsapp" in ((st.config or {}).get("channels") or []) for st in a.steps.all()):
            wa_autos += 1
    client_msgs = MessageTemplate.objects.exclude(group=TemplateGroup.TEAM)
    wa_msgs = sum(1 for t in client_msgs if (t.channels.get("whatsapp") or {}).get("on"))
    em_msgs = sum(1 for t in client_msgs if (t.channels.get("email") or {}).get("on"))

    def n(count, one, many):
        return f"{count} {one if count == 1 else many}"

    return {
        "whatsapp": [{"label": n(wa_autos, "automation", "automations"), "path": "/automations"},
                     {"label": n(wa_msgs, "client message", "client messages"), "path": "/emails"},
                     {"label": "Invite links", "path": "/approvals"}],
        "email_domain": [{"label": n(em_msgs, "client message", "client messages"), "path": "/emails"},
                         {"label": "Team alerts and digest", "path": "/emails?tab=alerts"},
                         {"label": "Forms sent by email", "path": "/forms"}],
        "health": [{"label": "Client profiles", "path": "/clients"},
                   {"label": "Habits (steps)", "path": "/habits"},
                   {"label": "Daily check-in", "path": "/forms"}],
    }


def listing(kind=None):
    from .serializers import IntegrationSerializer

    rows = {r.kind: r for r in Integration.objects.all()}
    for k in Integration.ORDER:
        if k not in rows:
            rows[k] = Integration.objects.create(kind=k, status=Integration.Status.CONNECTED if k == "whatsapp"
                                                 else Integration.Status.NOT_CONNECTED)
    ctx = {"used": _used()}
    if kind:
        return IntegrationSerializer(rows[kind], context=ctx).data
    return IntegrationSerializer([rows[k] for k in Integration.ORDER], many=True, context=ctx).data


def apply_config(integ, data):
    """Connect / Save. The WhatsApp number is the same one as Emails & alerts → Sender."""
    from apps.notifications.models import NotificationSettings

    if integ.kind == Integration.Kind.WHATSAPP and data.get("number"):
        cfg = NotificationSettings.load()
        cfg.whatsapp_number = data["number"]
        cfg.save(update_fields=["whatsapp_number"])
    elif integ.kind == Integration.Kind.EMAIL_DOMAIN and data.get("domain"):
        if data["domain"] != (integ.config or {}).get("domain"):
            integ.config = {"domain": data["domain"]}  # a new domain is checked from scratch
            integ.status = Integration.Status.PENDING
    elif integ.kind == Integration.Kind.HEALTH and data.get("types"):
        integ.config = {**(integ.config or {}), "types": data["types"]}


def _txt(name):
    """TXT records of a name, via DNS over HTTPS (no extra library). Raises on network trouble."""
    r = httpx.get("https://dns.google/resolve", params={"name": name, "type": "TXT"}, timeout=8)
    r.raise_for_status()
    return [a.get("data", "").replace('" "', "").strip('"') for a in r.json().get("Answer") or [] if a.get("type") == 16]


def check_domain(integ):
    """Look up SPF, DKIM and DMARC. All three found → connected (emails switch to the own address) and the
    owner gets an email, as the toast promises."""
    domain = (integ.config or {}).get("domain")
    if not domain:
        return integ
    was = integ.status
    records = []
    try:
        for label, host, start in DNS_RECORDS:
            name = domain if host == "@" else f"{host}.{domain}"
            ok = any(t.lower().startswith(start) for t in _txt(name))
            records.append({"label": label, "host": f"TXT · {host}", "ok": ok})
    except (httpx.HTTPError, ValueError) as exc:
        log.warning("DNS check for %s failed: %s", domain, exc)
        integ.config = {**integ.config, "checked_at": timezone.now().isoformat(), "check_failed": True}
        return integ
    integ.config = {**integ.config, "records": records, "checked_at": timezone.now().isoformat(), "check_failed": False}
    if all(r["ok"] for r in records):
        integ.status = Integration.Status.CONNECTED
        if was != Integration.Status.CONNECTED:
            _tell_owner(f"hello@{domain}")
    elif was == Integration.Status.CONNECTED:
        integ.status = Integration.Status.PENDING  # a record was removed: back to the platform address
    return integ


def _tell_owner(address):
    from apps.accounts.models import Role, User
    from apps.notifications.models import Channel
    from apps.notifications.services import notify

    admins = list(User.objects.filter(role=Role.ADMIN, is_active=True))
    notify(admins, "integration", "Your email domain is verified",
           f"All three DNS records are in place. Emails now come from {address}.",
           channels=[Channel.IN_APP, Channel.EMAIL], data={"path": "/settings?tab=i"})


def recheck_pending_domain():
    """Hourly while the domain waits for DNS (beat "email-domain-check")."""
    integ = Integration.objects.filter(kind=Integration.Kind.EMAIL_DOMAIN, status=Integration.Status.PENDING).first()
    if integ:
        check_domain(integ)
        integ.save()
    return integ
