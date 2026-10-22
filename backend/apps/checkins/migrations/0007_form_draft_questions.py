from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("checkins", "0006_onboarding_profile"),
    ]

    operations = [
        migrations.AddField(
            model_name="form",
            name="draft_questions",
            field=models.JSONField(blank=True, null=True),
        ),
    ]
