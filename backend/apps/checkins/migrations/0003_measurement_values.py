from django.db import migrations, models


def to_values(apps, schema_editor):
    """waist / hips / chest / arm / body fat columns → values; "arm" was one arm, kept as both biceps."""
    Measurement = apps.get_model("checkins", "Measurement")
    for m in Measurement.objects.all():
        v = {}
        for col, key in (("waist_cm", "waist"), ("hips_cm", "hips"), ("chest_cm", "chest"), ("body_fat_pct", "body_fat")):
            if getattr(m, col) is not None:
                v[key] = float(getattr(m, col))
        if m.arm_cm is not None:
            v["bicep_l"] = v["bicep_r"] = float(m.arm_cm)
        m.values = v
        m.save(update_fields=["values"])


class Migration(migrations.Migration):
    dependencies = [("checkins", "0002_board_checkin_questions")]

    operations = [
        migrations.AddField(model_name="measurement", name="values", field=models.JSONField(blank=True, default=dict)),
        migrations.RunPython(to_values, migrations.RunPython.noop),
        migrations.RemoveField(model_name="measurement", name="waist_cm"),
        migrations.RemoveField(model_name="measurement", name="hips_cm"),
        migrations.RemoveField(model_name="measurement", name="chest_cm"),
        migrations.RemoveField(model_name="measurement", name="arm_cm"),
        migrations.RemoveField(model_name="measurement", name="body_fat_pct"),
    ]
