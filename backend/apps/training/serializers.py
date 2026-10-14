from django.db.models import Count
from rest_framework import serializers

from .models import (
    Equipment,
    Exercise,
    Level,
    LogType,
    Muscle,
    Program,
    ProgramAssignment,
    ProgramDay,
    ProgramExercise,
    ProgramWeek,
    SetLog,
    WorkoutLog,
)

ALSO_LEVELS = {"light", "strong"}


def _clean_lines(lines, field, max_items=20):
    out = [" ".join(str(x).split()) for x in (lines or [])]
    out = [x for x in out if x]
    if len(out) > max_items:
        raise serializers.ValidationError({field: [f"Keep it to {max_items} lines."]})
    return out


class ExerciseSerializer(serializers.ModelSerializer):
    programs = serializers.IntegerField(read_only=True, source="n_programs", default=0)
    video_title = serializers.CharField(source="video.title", read_only=True, default=None)
    source = serializers.SerializerMethodField()

    class Meta:
        model = Exercise
        fields = ["id", "name", "muscle_group", "primary_muscle", "also_works", "equipment", "level", "is_builtin",
                  "source", "video", "video_title", "youtube_url", "cover_at_seconds", "how_to", "form_cues",
                  "log_type", "default_sets", "default_reps", "default_rest_seconds", "default_rpe",
                  "default_tempo", "duplicated_from", "programs", "created_at", "updated_at"]
        read_only_fields = ["is_builtin", "duplicated_from"]

    def get_source(self, obj):
        return "builtin" if obj.is_builtin else "custom"

    def validate_name(self, v):
        v = " ".join(v.split())
        if len(v) < 2:
            raise serializers.ValidationError("Enter the exercise name.")
        return v

    def validate_also_works(self, v):
        if not isinstance(v, list) or len(v) > 8:
            raise serializers.ValidationError("Up to 8 muscles.")
        out = []
        for row in v:
            if not isinstance(row, dict) or not str(row.get("muscle", "")).strip():
                raise serializers.ValidationError("Each row needs a muscle.")
            level = row.get("level", "light")
            if level not in ALSO_LEVELS:
                raise serializers.ValidationError("Level is light or strong.")
            out.append({"muscle": str(row["muscle"]).strip()[:40], "level": level})
        return out

    def validate(self, attrs):
        for f in ("how_to", "form_cues"):
            if f in attrs:
                attrs[f] = _clean_lines(attrs[f], f)
        if self.instance is not None and self.instance.is_builtin:
            raise serializers.ValidationError("Built-in exercises can't be edited. Use Duplicate to edit.")
        return attrs


class ExerciseMiniSerializer(serializers.ModelSerializer):
    class Meta:
        model = Exercise
        fields = ["id", "name", "muscle_group", "primary_muscle", "equipment", "level", "log_type", "default_sets",
                  "default_reps", "default_rest_seconds", "default_rpe", "default_tempo", "video", "youtube_url"]


# ---------------------------------------------------------------- program tree
class ProgramExerciseSerializer(serializers.ModelSerializer):
    id = serializers.IntegerField(required=False)
    exercise_detail = ExerciseMiniSerializer(source="exercise", read_only=True)
    edited = serializers.SerializerMethodField()

    class Meta:
        model = ProgramExercise
        fields = ["id", "exercise", "exercise_detail", "order", "superset_group", "sets", "reps", "rpe",
                  "rest_seconds", "tempo", "target_weight_kg", "note", "override", "edited"]

    def get_edited(self, obj):
        return bool(obj.override)

    def validate_override(self, v):
        allowed = {"name", "video", "youtube_url", "how_to", "form_cues"}
        if not isinstance(v, dict) or set(v) - allowed:
            raise serializers.ValidationError("Only name, video and steps can be changed for a program.")
        for f in ("how_to", "form_cues"):
            if f in v:
                v[f] = _clean_lines(v[f], f)
        return v

    def validate_reps(self, v):
        v = v.strip()
        if not v:
            raise serializers.ValidationError("Enter reps, e.g. 8–10, AMRAP, 45 s.")
        return v


class ProgramDaySerializer(serializers.ModelSerializer):
    id = serializers.IntegerField(required=False)
    exercises = ProgramExerciseSerializer(many=True, required=False)

    class Meta:
        model = ProgramDay
        fields = ["id", "weekday", "name", "is_rest", "rest_note", "exercises"]


class ProgramWeekSerializer(serializers.ModelSerializer):
    id = serializers.IntegerField(required=False)
    days = ProgramDaySerializer(many=True, required=False)

    class Meta:
        model = ProgramWeek
        fields = ["id", "number", "days"]


class ProgramCardSerializer(serializers.ModelSerializer):
    """Programs page card."""

    clients = serializers.SerializerMethodField()
    client_count = serializers.IntegerField(read_only=True, source="n_clients", default=0)
    week_pattern = serializers.SerializerMethodField()
    archived = serializers.SerializerMethodField()

    class Meta:
        model = Program
        fields = ["id", "name", "goal_line", "weeks", "days_per_week", "is_master", "archived", "archived_at",
                  "client_count", "clients", "week_pattern", "updated_at", "created_at"]
        read_only_fields = ["archived_at", "is_master"]

    def get_archived(self, obj):
        return obj.archived_at is not None

    def get_clients(self, obj):
        rows = getattr(obj, "_preview_clients", None)
        if rows is None:
            rows = [a.client for a in obj.assignments.filter(status="active").select_related("client")[:3]]
        return [{"id": str(u.id), "initials": u.initials, "avatar_color": u.avatar_color, "full_name": u.full_name}
                for u in rows]

    def get_week_pattern(self, obj):
        """7 dots for week 1: true = training day."""
        days = getattr(obj, "_week1", None)
        if days is None:
            days = {d.weekday: not d.is_rest for d in ProgramDay.objects.filter(week__program=obj, week__number=1)}
        return [bool(days.get(i)) for i in range(7)]


class ProgramDetailSerializer(ProgramCardSerializer):
    program_weeks = ProgramWeekSerializer(many=True, read_only=True)

    class Meta(ProgramCardSerializer.Meta):
        fields = ProgramCardSerializer.Meta.fields + ["master", "program_weeks"]


class ProgramCreateSerializer(serializers.ModelSerializer):
    class Meta:
        model = Program
        fields = ["id", "name", "goal_line", "weeks", "days_per_week"]

    def validate_name(self, v):
        v = " ".join(v.split())
        if len(v) < 2:
            raise serializers.ValidationError("Enter a program name.")
        return v

    def validate_weeks(self, v):
        if not 1 <= v <= 24:
            raise serializers.ValidationError("1 to 24 weeks.")
        return v


class StructureSerializer(serializers.Serializer):
    """The whole week/day/exercise tree, sent by the builder after each change (ids keep logs linked)."""

    weeks = ProgramWeekSerializer(many=True)

    def validate_weeks(self, weeks):
        nums = [w["number"] for w in weeks]
        if len(nums) != len(set(nums)) or not weeks or len(weeks) > 52:
            raise serializers.ValidationError("Weeks must be 1..N with no repeats.")
        for w in weeks:
            wd = [d["weekday"] for d in w.get("days", [])]
            if len(wd) != len(set(wd)) or any(x > 6 for x in wd):
                raise serializers.ValidationError(f"Week {w['number']} has the same day twice.")
            for d in w.get("days", []):
                if len(d.get("exercises", [])) > 30:
                    raise serializers.ValidationError("Up to 30 exercises a day.")
        return weeks


class AssignSerializer(serializers.Serializer):
    clients = serializers.ListField(child=serializers.UUIDField(), max_length=500)
    start_date = serializers.DateField(required=False, allow_null=True)
    when = serializers.ChoiceField(choices=["now", "after_current"], default="now")


class AssignmentSerializer(serializers.ModelSerializer):
    program_name = serializers.CharField(source="effective_program.name", read_only=True)
    weeks = serializers.IntegerField(source="effective_program.weeks", read_only=True)
    custom = serializers.SerializerMethodField()
    client = serializers.SerializerMethodField()

    class Meta:
        model = ProgramAssignment
        fields = ["id", "client", "program", "custom_program", "program_name", "weeks", "custom", "start_date",
                  "end_date", "status", "created_at"]

    def get_custom(self, obj):
        return obj.custom_program_id is not None

    def get_client(self, obj):
        u = obj.client
        return {"id": str(u.id), "full_name": u.full_name, "initials": u.initials, "avatar_color": u.avatar_color}


# ---------------------------------------------------------------- logging
class SetLogSerializer(serializers.ModelSerializer):
    volume = serializers.FloatField(read_only=True)

    class Meta:
        model = SetLog
        fields = ["id", "program_exercise", "exercise", "set_number", "weight_kg", "reps", "seconds",
                  "is_bodyweight", "is_warmup", "done", "done_at", "is_pr", "volume"]
        read_only_fields = ["is_pr", "done_at"]


class WorkoutLogSerializer(serializers.ModelSerializer):
    sets = SetLogSerializer(many=True, read_only=True)

    class Meta:
        model = WorkoutLog
        fields = ["id", "assignment", "program_day", "name", "date", "status", "started_at", "finished_at",
                  "duration_seconds", "time_breakdown", "effort", "note", "sets_done", "sets_planned", "auto_saved",
                  "sets"]
        read_only_fields = ["status", "finished_at", "sets_done", "sets_planned", "auto_saved", "assignment",
                            "started_at"]


class WorkoutRowSerializer(serializers.ModelSerializer):
    class Meta:
        model = WorkoutLog
        fields = ["id", "name", "date", "status", "duration_seconds", "effort", "sets_done", "sets_planned",
                  "finished_at", "note"]


class FinishSerializer(serializers.Serializer):
    effort = serializers.IntegerField(min_value=1, max_value=10, required=False, allow_null=True)
    note = serializers.CharField(max_length=2000, required=False, allow_blank=True)
    duration_seconds = serializers.IntegerField(min_value=0, max_value=24 * 3600, required=False)
    time_breakdown = serializers.DictField(child=serializers.IntegerField(min_value=0), required=False)


CHOICES = {
    "muscle": Muscle.choices, "equipment": Equipment.choices, "level": Level.choices, "log_type": LogType.choices,
}


def facet_counts(qs):
    """Filter panel: options with counts for Muscle / Equipment / Level / Source."""
    def counts(field):
        return dict(qs.order_by().values_list(field).annotate(n=Count("id")))

    m, e, lv = counts("muscle_group"), counts("equipment"), counts("level")
    src = dict(qs.order_by().values_list("is_builtin").annotate(n=Count("id")))
    return {
        "muscle": [{"value": k, "label": v, "count": m.get(k, 0)} for k, v in Muscle.choices],
        "equipment": [{"value": k, "label": v, "count": e.get(k, 0)} for k, v in Equipment.choices],
        "level": [{"value": k, "label": v, "count": lv.get(k, 0)} for k, v in Level.choices],
        "source": [{"value": "builtin", "label": "Built-in", "count": src.get(True, 0)},
                   {"value": "custom", "label": "Custom", "count": src.get(False, 0)}],
    }
