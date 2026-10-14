from rest_framework import serializers

from .models import Habit, SupplementItem, SupplementPlan

QUICK_ADD = [
    {"name": "Vitamin D3", "dose": "1 tablet", "timing": "breakfast", "with_food": True},
    {"name": "Electrolytes", "dose": "1 sachet", "timing": "post_workout", "with_food": False},
    {"name": "Caffeine", "dose": "100 mg", "timing": "morning", "with_food": False},
    {"name": "Iron", "dose": "1 tablet", "timing": "breakfast", "with_food": True},
    {"name": "B12", "dose": "1 tablet", "timing": "breakfast", "with_food": True},
    {"name": "Fibre (psyllium)", "dose": "1 tsp · 5 g", "timing": "before_bed", "with_food": False},
    {"name": "Probiotic", "dose": "1 capsule", "timing": "breakfast", "with_food": True},
    {"name": "Ashwagandha", "dose": "1 capsule", "timing": "before_bed", "with_food": False},
]


class HabitSerializer(serializers.ModelSerializer):
    client_count = serializers.IntegerField(read_only=True, source="n_clients", default=0)
    frequency_label = serializers.SerializerMethodField()

    class Meta:
        model = Habit
        fields = ["id", "name", "kind", "target", "unit", "frequency", "days", "times_per_week", "icon", "why",
                  "client_count", "frequency_label", "updated_at", "created_at"]

    def get_frequency_label(self, obj):
        if obj.frequency == Habit.Frequency.DAYS:
            names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            return ", ".join(names[d] for d in sorted(obj.days or []))
        if obj.frequency == Habit.Frequency.TIMES_WEEK:
            return f"{obj.times_per_week} times a week"
        return "Daily"

    def validate_name(self, v):
        v = " ".join(v.split())
        if len(v) < 2:
            raise serializers.ValidationError("Enter the habit name.")
        return v

    def validate_icon(self, v):
        if v not in Habit.ICONS:
            raise serializers.ValidationError("Pick an icon.")
        return v

    def validate(self, attrs):
        inst = self.instance
        kind = attrs.get("kind", inst.kind if inst else Habit.Kind.TICK)
        freq = attrs.get("frequency", inst.frequency if inst else Habit.Frequency.DAILY)
        if kind == Habit.Kind.COUNTER:
            target = attrs.get("target", inst.target if inst else None)
            if not target or target < 1:
                raise serializers.ValidationError({"target": ["A counter needs a target."]})
        else:
            attrs["target"] = None
        if freq == Habit.Frequency.DAYS:
            days = attrs.get("days", inst.days if inst else [])
            if not days or any(d > 6 for d in days):
                raise serializers.ValidationError({"days": ["Pick at least one day."]})
            attrs["days"] = sorted(set(days))
        if freq == Habit.Frequency.TIMES_WEEK:
            n = attrs.get("times_per_week", inst.times_per_week if inst else None)
            if not n:
                raise serializers.ValidationError({"times_per_week": ["How many times a week?"]})
        return attrs


class SupplementItemSerializer(serializers.ModelSerializer):
    id = serializers.IntegerField(required=False)

    class Meta:
        model = SupplementItem
        fields = ["id", "name", "dose", "how", "timing", "days", "with_food"]

    def validate_days(self, v):
        if any(d > 6 for d in v):
            raise serializers.ValidationError("Days are 0 (Mon) to 6 (Sun).")
        return sorted(set(v))


class SupplementPlanSerializer(serializers.ModelSerializer):
    items = SupplementItemSerializer(many=True, required=False)
    client_count = serializers.IntegerField(read_only=True, source="n_clients", default=0)

    class Meta:
        model = SupplementPlan
        fields = ["id", "name", "note", "items", "client_count", "updated_at", "created_at"]

    def validate_name(self, v):
        v = " ".join(v.split())
        if len(v) < 2:
            raise serializers.ValidationError("Enter the plan name.")
        return v

    def _save_items(self, plan, items):
        keep = []
        for i, d in enumerate(items):
            obj = plan.items.filter(id=d.get("id")).first() if d.get("id") else None
            obj = obj or SupplementItem(plan=plan)
            for k, v in d.items():
                if k != "id":
                    setattr(obj, k, v)
            obj.order = i
            obj.save()
            keep.append(obj.id)
        plan.items.exclude(id__in=keep).delete()

    def create(self, validated):
        items = validated.pop("items", [])
        plan = SupplementPlan.objects.create(**validated)
        self._save_items(plan, items)
        return plan

    def update(self, plan, validated):
        items = validated.pop("items", None)
        for k, v in validated.items():
            setattr(plan, k, v)
        plan.save()
        if items is not None:
            self._save_items(plan, items)
        return plan
