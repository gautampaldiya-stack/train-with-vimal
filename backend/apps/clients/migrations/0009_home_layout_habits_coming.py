"""Habits and Coming up became Home layout cards (Probid 2026-11-04). A layout saved before then had them fixed at
the bottom, so they go at its end; a client who never saved a layout gets the default list."""
from django.db import migrations


def add_cards(apps, schema_editor):
    ClientProfile = apps.get_model("clients", "ClientProfile")
    for cp in ClientProfile.objects.exclude(home_layout=None).only("id", "home_layout"):
        layout = list(cp.home_layout or [])
        if not layout:
            continue
        changed = False
        for k in ("habits", "coming"):
            if k not in layout:
                layout.append(k)
                changed = True
        if changed:
            ClientProfile.objects.filter(id=cp.id).update(home_layout=layout)


class Migration(migrations.Migration):
    dependencies = [("clients", "0008_client_home_layout")]
    operations = [migrations.RunPython(add_cards, migrations.RunPython.noop)]
