from django.db import migrations

# A PC database (Oct-28 backup) had checkins 0010 recorded, then the Oct-28 clean-up dropped the old
# `description` column and 0010 did not run again: put the column back when it is missing.
SQL = """
ALTER TABLE checkins_form ADD COLUMN IF NOT EXISTS description varchar(300) NOT NULL DEFAULT '';
ALTER TABLE checkins_form ALTER COLUMN description DROP DEFAULT;
"""


class Migration(migrations.Migration):

    dependencies = [
        ("checkins", "0010_form_description"),
        ("training", "0009_rest_timers"),
    ]

    operations = [migrations.RunSQL(SQL, migrations.RunSQL.noop)]
