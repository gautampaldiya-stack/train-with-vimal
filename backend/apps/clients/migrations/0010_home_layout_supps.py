"""Supplements became a Home layout card too (Probid 2026-11-04): saved layouts get it at the end."""
from django.db import migrations


def add_card(apps, schema_editor):
    ClientProfile = apps.get_model("clients", "ClientProfile")
    for cp in ClientProfile.objects.exclude(home_layout=None).only("id", "home_layout"):
        layout = list(cp.home_layout or [])
        if layout and "supps" not in layout:
            ClientProfile.objects.filter(id=cp.id).update(home_layout=layout + ["supps"])


class Migration(migrations.Migration):
    dependencies = [("clients", "0009_home_layout_habits_coming")]
    operations = [migrations.RunPython(add_card, migrations.RunPython.noop)]
