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


def exercise_perm(user):
    """Vimal, or a trainer with "Add custom exercises" (training.custom_exercises)."""
    if user.is_admin:
        return True
    return bool(user.is_trainer and user.trainer_profile.has_perm("training.custom_exercises"))


def youtube_thumb(url):
    """https://youtu.be/<id>, youtube.com/watch?v=<id> or /shorts/<id> → the video's still image."""
    import re

    m = re.search(r"(?:youtu\.be/|v=|/shorts/|/embed/)([A-Za-z0-9_-]{11})", url or "")
    return f"https://img.youtube.com/vi/{m.group(1)}/mqdefault.jpg" if m else None


class ExerciseSerializer(serializers.ModelSerializer):
    programs = serializers.IntegerField(read_only=True, source="n_programs", default=0)
    video_title = serializers.CharField(source="video.title", read_only=True, default=None)
    source = serializers.SerializerMethodField()
    thumb = serializers.SerializerMethodField()
    media = serializers.SerializerMethodField()
    cover_image = serializers.SerializerMethodField()
    can_edit = serializers.SerializerMethodField()
    # empty lines are dropped in validate()
    how_to = serializers.ListField(child=serializers.CharField(max_length=300, allow_blank=True), required=False)
    form_cues = serializers.ListField(child=serializers.CharField(max_length=300, allow_blank=True), required=False)

    class Meta:
        model = Exercise
        fields = ["id", "name", "muscle_group", "primary_muscle", "also_works", "equipment", "level", "is_builtin",
                  "source", "video", "video_title", "youtube_url", "thumb", "media", "cover_at_seconds", "cover_image", "cover_frame",
                  "how_to", "form_cues", "log_type", "default_sets", "default_reps", "default_rest_seconds",
                  "default_rpe", "default_tempo", "duplicated_from", "programs", "can_edit", "created_at", "updated_at"]
        read_only_fields = ["is_builtin", "duplicated_from"]

    def _url(self, f):
        req = self.context.get("request")
        return req.build_absolute_uri(f.url) if req else f.url

    def get_cover_image(self, obj):
        return self._url(obj.cover_image) if obj.cover_image else None

    def get_can_edit(self, obj):
        """Built-in exercises never change (Duplicate to edit); custom ones need "Add custom exercises"."""
        user = getattr(self.context.get("request"), "user", None)
        return bool(user and not obj.is_builtin and exercise_perm(user))

    def get_source(self, obj):
        return "builtin" if obj.is_builtin else "custom"

    def get_media(self, obj):
        """The video or picture the guide shows (null: none uploaded; a YouTube link stays in youtube_url)."""
        from apps.content.library import media_of

        return media_of(obj.video, self.context.get("request"))

    def get_thumb(self, obj):
        """Picture for the exercise tile: an uploaded cover, else the chosen video frame, else the video's cover, else
        the YouTube still, else none (icon)."""
        from .frames import key_url

        if obj.cover_image:
            return self._url(obj.cover_image)
        frame = key_url(obj.cover_frame, self.context.get("request"))
        if frame:
            return frame
        v = obj.video
        if v and v.kind == "image" and v.file:
            req = self.context.get("request")
            return req.build_absolute_uri(v.file.url) if req else v.file.url
        if v and v.cover:
            req = self.context.get("request")
            return req.build_absolute_uri(v.cover.url) if req else v.cover.url
        return youtube_thumb(obj.youtube_url or (v.youtube_url if v else ""))

    def validate_cover_frame(self, v):
        from .frames import KEY_RE

        v = (v or "").strip()
        if v and not KEY_RE.match(v):
            raise serializers.ValidationError("Pick one of the frames.")
        return v

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
            item = {"muscle": str(row["muscle"]).strip()[:40], "level": level}
            note = " ".join(str(row.get("note") or "").split())[:80]
            if note:
                item["note"] = note  # "Straighten the arms at the top" (Muscles tab)
            out.append(item)
        names = [x["muscle"].lower() for x in out]
        if len(set(names)) != len(names):
            raise serializers.ValidationError("Each muscle once.")
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
        fields = ["id", "name", "muscle_group", "primary_muscle", "also_works", "equipment", "level", "log_type",
                  "default_sets", "default_reps", "default_rest_seconds", "default_rpe", "default_tempo", "video",
                  "youtube_url", "how_to", "form_cues"]


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
    level_label = serializers.CharField(source="get_level_display", read_only=True)

    class Meta:
        model = Program
        fields = ["id", "name", "goal_line", "weeks", "days_per_week", "level", "level_label", "is_master",
                  "archived", "archived_at", "client_count", "clients", "week_pattern", "can_edit", "updated_at",
                  "created_at", "owner"]
        read_only_fields = ["archived_at", "is_master"]

    can_edit = serializers.SerializerMethodField()
    owner = serializers.SerializerMethodField()

    def get_archived(self, obj):
        return obj.archived_at is not None

    def get_owner(self, obj):
        """Who made it (card tag, builder line): the gym's own (Vimal / seeded), the viewer, or another trainer."""
        u = obj.created_by
        req = self.context.get("request")
        if u is None or u.is_admin:
            return {"kind": "gym", "name": "Gym", "label": "Gym program"}
        if req and u.id == req.user.id:
            return {"kind": "you", "name": "You", "label": "Made by you"}
        return {"kind": "trainer", "name": u.first_name or u.full_name, "label": f"Made by {u.full_name}"}

    def get_can_edit(self, obj):
        """Rename, days, archive, delete (D-39). False without a request (e.g. a background job)."""
        from .services import can_edit_program

        req = self.context.get("request")
        return bool(req and can_edit_program(req.user, obj))

    def get_clients(self, obj):
        rows = getattr(obj, "_preview_clients", None)
        if rows is None:
            qs = obj.assignments.filter(status="active").select_related("client").order_by("-created_at")
            req = self.context.get("request")
            if req and req.user.is_trainer:
                from apps.clients.services import visible_clients

                qs = qs.filter(client__in=visible_clients(req.user))
            rows = [a.client for a in qs[:3]]
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
        fields = ["id", "name", "goal_line", "weeks", "days_per_week", "level"]

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
    master_name = serializers.CharField(source="program.name", read_only=True)
    days_per_week = serializers.IntegerField(source="effective_program.days_per_week", read_only=True)
    assigned_by = serializers.SerializerMethodField()
    week = serializers.SerializerMethodField()

    class Meta:
        model = ProgramAssignment
        fields = ["id", "client", "program", "custom_program", "program_name", "weeks", "custom", "start_date",
                  "end_date", "status", "end_reason", "created_at", "master_name", "days_per_week", "assigned_by", "week"]

    def get_assigned_by(self, obj):
        return obj.assigned_by.full_name if obj.assigned_by_id and obj.assigned_by else None

    def get_week(self, obj):
        """Week of the plan the client is on today (1-based, capped at the plan length); None before it starts."""
        from django.utils import timezone

        today = timezone.localdate()
        if obj.start_date > today:
            return None
        return min((today - obj.start_date).days // 7 + 1, obj.effective_program.weeks)

    def get_custom(self, obj):
        return obj.custom_program_id is not None

    def get_client(self, obj):
        u = obj.client
        return {"id": str(u.id), "full_name": u.full_name, "initials": u.initials, "avatar_color": u.avatar_color}


# ---------------------------------------------------------------- logging
class SetLogSerializer(serializers.ModelSerializer):
    volume = serializers.SerializerMethodField()
    exercise_name = serializers.CharField(source="exercise.name", read_only=True)
    log_type = serializers.CharField(source="exercise.log_type", read_only=True)

    class Meta:
        model = SetLog
        fields = ["id", "program_exercise", "exercise", "exercise_name", "log_type", "set_number", "weight_kg",
                  "reps", "seconds", "distance_km", "is_bodyweight", "is_warmup", "done", "done_at", "is_pr",
                  "volume", "client_key"]
        read_only_fields = ["is_pr", "done_at"]

    def get_volume(self, obj):
        """Bodyweight sets count the client's weight that day (+ added load); see `services.set_volume`."""
        from .services import body_weights, set_volume

        body = None
        if obj.is_bodyweight and obj.done and obj.reps and not obj.is_warmup and obj.workout_id:
            w = obj.workout
            cache = self.context.setdefault("_body_weights", {}) if isinstance(self.context, dict) else {}
            if w.client_id not in cache:
                cache[w.client_id] = body_weights(w.client_id)
            body = cache[w.client_id](w.date)
        return set_volume(obj, body)


class WorkoutLogSerializer(serializers.ModelSerializer):
    sets = SetLogSerializer(many=True, read_only=True)

    class Meta:
        model = WorkoutLog
        fields = ["id", "assignment", "program_day", "name", "date", "status", "started_at", "finished_at",
                  "duration_seconds", "time_breakdown", "effort", "note", "sets_done", "sets_planned", "auto_saved",
                  "paused_at", "reopened_at", "sets"]
        read_only_fields = ["status", "finished_at", "sets_done", "sets_planned", "auto_saved", "assignment",
                            "started_at", "paused_at", "reopened_at"]


class WorkoutRowSerializer(serializers.ModelSerializer):
    """Past workouts row: "45 min · 6 exercises · 19 sets" and a PR flag."""

    exercises = serializers.SerializerMethodField()
    has_pr = serializers.SerializerMethodField()

    class Meta:
        model = WorkoutLog
        fields = ["id", "name", "date", "status", "duration_seconds", "effort", "sets_done", "sets_planned",
                  "finished_at", "note", "program_day", "exercises", "has_pr"]

    def _sets(self, obj):
        cache = getattr(obj, "_prefetched_objects_cache", {})
        return cache["sets"] if "sets" in cache else list(obj.sets.all())

    def get_exercises(self, obj):
        return len({s.exercise_id for s in self._sets(obj) if s.done})

    def get_has_pr(self, obj):
        return any(s.is_pr for s in self._sets(obj))


class FinishSerializer(serializers.Serializer):
    effort = serializers.IntegerField(min_value=1, max_value=10, required=False, allow_null=True)
    note = serializers.CharField(max_length=2000, required=False, allow_blank=True)
    duration_seconds = serializers.IntegerField(min_value=0, max_value=24 * 3600, required=False)
    time_breakdown = serializers.DictField(child=serializers.IntegerField(min_value=0), required=False)


class StateSetSerializer(serializers.Serializer):
    """One set in 'save the workout as it is now' (`PUT me/workouts/<id>/state/`)."""

    id = serializers.IntegerField(required=False, allow_null=True)
    key = serializers.CharField(max_length=40, required=False, allow_blank=True)
    exercise = serializers.PrimaryKeyRelatedField(queryset=Exercise.objects.all())
    program_exercise = serializers.IntegerField(required=False, allow_null=True)
    set_number = serializers.IntegerField(min_value=1, max_value=50)
    weight_kg = serializers.DecimalField(max_digits=6, decimal_places=2, required=False, allow_null=True,
                                         min_value=-200, max_value=1000)
    reps = serializers.IntegerField(min_value=0, max_value=1000, required=False, allow_null=True)
    seconds = serializers.IntegerField(min_value=0, max_value=24 * 3600, required=False, allow_null=True)
    distance_km = serializers.DecimalField(max_digits=6, decimal_places=2, required=False, allow_null=True,
                                           min_value=0, max_value=500)
    is_bodyweight = serializers.BooleanField(default=False)
    is_warmup = serializers.BooleanField(default=False)
    done = serializers.BooleanField(default=False)
    done_at = serializers.DateTimeField(required=False, allow_null=True)


class StateSerializer(serializers.Serializer):
    started_at = serializers.DateTimeField(required=False)
    paused_at = serializers.DateTimeField(required=False, allow_null=True)
    sets = StateSetSerializer(many=True)

    def validate_sets(self, v):
        if len(v) > 200:
            raise serializers.ValidationError("Send up to 200 sets.")
        return v


class FeedbackSerializer(serializers.Serializer):
    effort = serializers.IntegerField(min_value=1, max_value=10)
    note = serializers.CharField(max_length=2000, required=False, allow_blank=True)


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
