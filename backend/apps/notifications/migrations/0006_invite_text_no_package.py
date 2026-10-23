from django.db import migrations

OLD = "Create your account to see your plan: {{package_name}}."
NEW = "Create your account to see your plan."


def drop_package(apps, schema_editor):
    """Packages are not used for now (Gautam 2026-10-23): the client invite no longer says "plan: <package>"."""
    for t in apps.get_model("notifications", "MessageTemplate").objects.filter(key="client-invite"):
        email = (t.channels or {}).get("email") or {}
        if OLD in (email.get("body") or ""):
            email["body"] = email["body"].replace(OLD, NEW)
            t.save(update_fields=["channels"])


class Migration(migrations.Migration):
    dependencies = [("notifications", "0005_digest_off_by_default")]
    operations = [migrations.RunPython(drop_package, migrations.RunPython.noop)]
