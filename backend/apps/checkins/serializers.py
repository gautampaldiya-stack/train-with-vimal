from rest_framework import serializers

from apps.common.validators import IMAGE_EXTENSIONS

from .models import (
    CHOICE_TYPES,
    Answer,
    Form,
    FormRequest,
    MEASURES,
    Measurement,
    PhotoSet,
    ProgressPhoto,
    Question,
    QuestionType,
    Submission,
    WeightLog,
)

METRICS = {"", "weight", "height", "sleep_hours", "energy", "mood", "hunger", "soreness", "steps", *(k for k, _, _ in MEASURES)}


class QuestionSerializer(serializers.ModelSerializer):
    id = serializers.IntegerField(required=False, allow_null=True)

    class Meta:
        model = Question
        fields = ["id", "text", "type", "options", "scale_labels", "allow_other", "help_text", "required", "metric",
                  "profile_key"]
        # Set by the built-in onboarding questionnaire (which profile field a question fills); the builder keeps it.
        read_only_fields = ["profile_key"]

    def validate(self, attrs):
        t = attrs.get("type")
        text = " ".join((attrs.get("text") or "").split())
        if not text:
            raise serializers.ValidationError({"text": ["Enter the question."]})
        attrs["text"] = text
        opts = [" ".join(o.split()) for o in attrs.get("options", []) if o and o.strip()]
        if t in CHOICE_TYPES:
            # "No" + Other ("Any known food allergies?") is two choices too
            if len(opts) + (1 if attrs.get("allow_other") else 0) < 2:
                raise serializers.ValidationError({"options": ["Add at least two options."]})
            if len({o.lower() for o in opts}) != len(opts):
                raise serializers.ValidationError({"options": ["Two options are the same."]})
            if len(opts) > 30:
                raise serializers.ValidationError({"options": ["Up to 30 options."]})
        elif t == QuestionType.PHOTO:  # options = the photos it asks for ("Front", "Side", "Back"; "Meal"…)
            if len({o.lower() for o in opts}) != len(opts):
                raise serializers.ValidationError({"options": ["Two photos have the same name."]})
            if len(opts) > 6 or any(len(o) > 20 for o in opts):
                raise serializers.ValidationError({"options": ["Up to 6 photos, each name up to 20 letters."]})
            attrs["allow_other"] = False
        else:
            opts = []
            attrs["allow_other"] = False
        attrs["options"] = opts
        if t == QuestionType.SCALE:
            labels = attrs.get("scale_labels") or []
            if labels and len(labels) != 5:
                raise serializers.ValidationError({"scale_labels": ["A scale has 5 labels."]})
        else:
            attrs["scale_labels"] = []
        if attrs.get("metric", "") not in METRICS:
            raise serializers.ValidationError({"metric": ["Unknown metric."]})
        return attrs


class FormRowSerializer(serializers.ModelSerializer):
    question_count = serializers.IntegerField(read_only=True, source="n_questions", default=0)
    sent_by = serializers.SerializerMethodField()
    built_in = serializers.SerializerMethodField()
    has_draft = serializers.SerializerMethodField()

    class Meta:
        model = Form
        fields = ["id", "name", "type", "status", "is_parq", "question_count", "sent_by", "built_in", "has_draft",
                  "updated_at", "created_at"]
        read_only_fields = ["status", "is_parq"]

    def get_sent_by(self, obj):
        names = (self.context.get("senders") or {}).get(obj.id, [])
        return names

    def get_built_in(self, obj):
        """ "How it is sent" when no automation sends it: how the app asks it (D-50), else ""."""
        from .library import built_in

        live = self.context.get("live")
        return built_in(obj, live) if live is not None else ""

    def get_has_draft(self, obj):
        return obj.draft_questions is not None

    def validate_name(self, v):
        v = " ".join(v.split())
        if len(v) < 2:
            raise serializers.ValidationError("Enter a form name.")
        return v


class FormDetailSerializer(FormRowSerializer):
    questions = serializers.SerializerMethodField()

    def get_questions(self, obj):
        """The builder's list: the unpublished draft when there is one (D-50), else the live questions."""
        if obj.draft_questions is not None:
            return obj.draft_questions
        return QuestionSerializer([q for q in obj.questions.all() if not q.is_removed], many=True).data

    class Meta(FormRowSerializer.Meta):
        fields = FormRowSerializer.Meta.fields + ["questions"]


class FormCreateSerializer(serializers.Serializer):
    name = serializers.CharField(max_length=120)
    type = serializers.ChoiceField(choices=["onboarding", "weekly", "daily", "survey", "waiver"])
    start = serializers.ChoiceField(choices=["template", "blank"], default="template")


class QuestionsSerializer(serializers.Serializer):
    questions = QuestionSerializer(many=True)

    def validate_questions(self, v):
        # the built-in onboarding questionnaire alone has 57
        if len(v) > 80:
            raise serializers.ValidationError("Up to 80 questions.")
        return v


class AnswerSerializer(serializers.ModelSerializer):
    question_text = serializers.CharField(source="question.text", read_only=True)
    question_type = serializers.CharField(source="question.type", read_only=True)
    metric = serializers.CharField(source="question.metric", read_only=True)

    class Meta:
        model = Answer
        fields = ["id", "question", "question_text", "question_type", "metric", "value", "photo"]


def summary_line(sub):
    """'Weight 61.8 kg · energy 3/5 · knees sore'"""
    m = sub.metrics or {}
    parts = []
    if "weight" in m:
        parts.append(f"Weight {m['weight']} kg")
    if "sleep_hours" in m:
        parts.append(f"{m['sleep_hours']} h sleep")
    if "energy" in m:
        parts.append(f"energy {m['energy']}/5")
    if "mood" in m:
        parts.append(f"mood {m['mood']}/5")
    note = m.get("note")
    if note:
        parts.append(str(note)[:40])
    return " · ".join(parts)


class SubmissionRowSerializer(serializers.ModelSerializer):
    client = serializers.SerializerMethodField()
    form_name = serializers.CharField(source="form.name", read_only=True)
    summary = serializers.SerializerMethodField()
    reviewed = serializers.SerializerMethodField()
    photo_count = serializers.SerializerMethodField()

    class Meta:
        model = Submission
        fields = ["id", "client", "form", "form_name", "form_type", "date", "week_number", "metrics", "summary",
                  "reviewed", "reviewed_at", "reply", "photo_count", "edited_at", "created_at"]

    def get_client(self, obj):
        u = obj.client
        return {"id": str(u.id), "full_name": u.full_name, "initials": u.initials, "avatar_color": u.avatar_color}

    def get_summary(self, obj):
        return summary_line(obj)

    def get_reviewed(self, obj):
        return obj.reviewed_at is not None

    def get_photo_count(self, obj):
        n = getattr(obj, "n_photos", None)
        return n if n is not None else obj.answers.exclude(photo="").exclude(photo__isnull=True).count()


class SubmissionDetailSerializer(SubmissionRowSerializer):
    answers = AnswerSerializer(many=True, read_only=True)
    reviewed_by_name = serializers.CharField(source="reviewed_by.full_name", read_only=True, default=None)
    photos = serializers.SerializerMethodField()

    class Meta(SubmissionRowSerializer.Meta):
        fields = SubmissionRowSerializer.Meta.fields + ["answers", "reviewed_by_name", "photos"]

    def get_photos(self, obj):
        """Photos sent with this check-in, one for each slot the question asks for (Front, Side, Back…)."""
        from .client_page import answer_photos

        return answer_photos(obj, self.context.get("request"))


class ReviewSerializer(serializers.Serializer):
    reply = serializers.CharField(max_length=2000, required=False, allow_blank=True)


class FormRequestSerializer(serializers.ModelSerializer):
    form_name = serializers.CharField(source="form.name", read_only=True)
    form_type = serializers.CharField(source="form.type", read_only=True)
    question_count = serializers.SerializerMethodField()
    status = serializers.SerializerMethodField()

    class Meta:
        model = FormRequest
        fields = ["id", "form", "form_name", "form_type", "question_count", "due_at", "filled_at", "status",
                  "created_at"]
        read_only_fields = ["filled_at"]

    def get_question_count(self, obj):
        return obj.form.questions.filter(is_removed=False).count()

    def get_status(self, obj):
        return "filled" if obj.filled_at else "waiting"


class WeightLogSerializer(serializers.ModelSerializer):
    class Meta:
        model = WeightLog
        fields = ["id", "date", "weight_kg", "source", "created_at"]
        read_only_fields = ["source"]


class MeasurementSerializer(serializers.ModelSerializer):
    """`values` = {key: number}; a key set to null is taken off that day. Keys are MEASURES' keys."""

    class Meta:
        model = Measurement
        fields = ["id", "date", "values", "created_at"]

    def validate_values(self, v):
        if not isinstance(v, dict):
            raise serializers.ValidationError("Send the measurements as {name: number}.")
        units = {k: u for k, _, u in MEASURES}
        out = {}
        for k, n in v.items():
            if k not in units:
                raise serializers.ValidationError({k: ["Not a measurement we track."]})
            if n is None or n == "":
                out[k] = None
                continue
            try:
                n = round(float(n), 1)
            except (TypeError, ValueError):
                raise serializers.ValidationError({k: ["Enter a number."]})
            lo, hi = (3, 70) if units[k] == "%" else (10, 300)
            if not lo <= n <= hi:
                raise serializers.ValidationError({k: ["Check this number."]})
            out[k] = n
        if not out:
            raise serializers.ValidationError("Enter at least one measurement.")
        return out


class ProgressPhotoSerializer(serializers.ModelSerializer):
    class Meta:
        model = ProgressPhoto
        fields = ["id", "pose", "image", "created_at"]

    def validate_image(self, f):
        ext = f.name.rsplit(".", 1)[-1].lower()
        if ext not in IMAGE_EXTENSIONS:
            raise serializers.ValidationError("Upload a JPG, PNG or WebP photo.")
        if f.size > 10 * 1024 * 1024:
            raise serializers.ValidationError("Photos can be up to 10 MB.")
        return f


class PhotoSetSerializer(serializers.ModelSerializer):
    photos = ProgressPhotoSerializer(many=True, read_only=True)

    class Meta:
        model = PhotoSet
        fields = ["id", "label", "date", "weight_kg", "submission", "photos", "created_at"]
        read_only_fields = ["submission"]
