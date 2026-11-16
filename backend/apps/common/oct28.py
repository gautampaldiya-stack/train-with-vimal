"""Clean-up for databases that ran the Oct-28 backup migrations (D-61 … D-79, rolled back on 2026-10-28).

Those migrations were never on `develop` or the live server, but a PC database that migrated the old `working`
still has their columns and tables and their rows in `django_migrations`. Today's migrations then fail with
"column ... already exists" (training 0008 `set_type`, 0009 rest columns, checkins 0010 `description`), and the
old NOT NULL columns with no database default break inserts.

`undo_oct28(apps, schema_editor)` is called at the start of those migrations. For every old migration that the
database says it ran, it drops what that migration added and deletes its row. On any other database it does nothing.
"""

# old migration (app, name) → (columns as (table, column), tables)
OLD = {
    ("checkins", "0008_form_description_daily_note"): ([("checkins_form", "description")], []),
    ("checkins", "0009_question_uid_config"): ([("checkins_question", "uid"), ("checkins_question", "config")], []),
    ("clients", "0008_client_toggles_water"): (
        [
            ("clients_clientprofile", "daily_checkin_on"),
            ("clients_clientprofile", "water_ml"),
            ("clients_clientprofile", "water_on"),
            ("clients_clientprofile", "weekly_checkin_on"),
        ],
        [],
    ),
    ("clients", "0009_invite_link_is_main"): ([("clients_invitelink", "is_main")], []),
    ("content", "0006_upload_names"): ([], []),
    ("notifications", "0007_team_alerts_oct28"): ([], []),
    ("nutrition", "0008_plan_totals_from_foods"): ([], []),
    ("nutrition", "0009_upload_names"): ([], []),
    ("training", "0008_upload_names"): ([], []),
    ("training", "0009_logger_strong"): (
        [
            ("training_formvideo", "sent_at"),
            ("training_setlog", "rest_seconds"),
            ("training_setlog", "set_type"),
            ("training_workoutlog", "sessions"),
        ],
        ["training_focusmetric"],
    ),
    ("training", "0010_rest_timers"): (
        [
            ("training_programexercise", "rest_drop_seconds"),
            ("training_programexercise", "rest_warmup_seconds"),
            ("training_programexercise", "set_rests"),
            ("training_setlog", "rest_actual_seconds"),
            ("training_setlog", "rest_extra_seconds"),
            ("training_setlog", "rest_planned_seconds"),
        ],
        ["training_clientexerciserest"],
    ),
}


# columns that today's code also adds: keep them when today's migration for them already ran (it will not run again)
NEW_OWNER = {
    ("checkins_form", "description"): ("checkins", "0010_form_description"),
    ("training_setlog", "set_type"): ("training", "0008_logger_set_types_bpm_segments"),
    ("training_setlog", "rest_seconds"): ("training", "0009_rest_timers"),
    ("training_programexercise", "rest_warmup_seconds"): ("training", "0009_rest_timers"),
    ("training_programexercise", "rest_drop_seconds"): ("training", "0009_rest_timers"),
}


def undo_oct28(apps, schema_editor):
    conn = schema_editor.connection
    q = conn.ops.quote_name
    with conn.cursor() as cur:
        cur.execute("SELECT app, name FROM django_migrations")
        recorded = {tuple(r) for r in cur.fetchall()}
        ran = recorded & set(OLD)
        if not ran:
            return
        existing = set(conn.introspection.table_names(cur))
        for key in sorted(ran):
            columns, tables = OLD[key]
            for table in tables:
                if table in existing:
                    cur.execute(f"DROP TABLE {q(table)} CASCADE")
            for table, column in columns:
                if table in existing and NEW_OWNER.get((table, column)) not in recorded:
                    cur.execute(f"ALTER TABLE {q(table)} DROP COLUMN IF EXISTS {q(column)} CASCADE")
            cur.execute("DELETE FROM django_migrations WHERE app = %s AND name = %s", list(key))
