from django.db import migrations


def give_admins_a_profile(apps, schema_editor):
    User = apps.get_model("accounts", "User")
    TrainerProfile = apps.get_model("trainers", "TrainerProfile")
    for admin in User.objects.filter(role="admin"):
        TrainerProfile.objects.get_or_create(
            user=admin,
            defaults={"is_owner": True, "access_mode": "all", "max_clients": 40,
                      "speciality": [], "languages": ["Hindi", "English"]},
        )


class Migration(migrations.Migration):
    dependencies = [
        ("trainers", "0002_trainer_notify"),
        ("accounts", "0001_initial"),
    ]

    operations = [migrations.RunPython(give_admins_a_profile, migrations.RunPython.noop)]
