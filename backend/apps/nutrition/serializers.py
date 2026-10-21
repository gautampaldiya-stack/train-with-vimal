from decimal import Decimal

from rest_framework import serializers

from .models import FOOD_GROUPS, Diet, Food, FoodLogEntry, FoodUnit, Meal, MealItem, MealOption, MealPlan
from .swaps import amount_label, match_percent, resolve, same_kcal_grams  # noqa: F401

UNIT_SUGGESTIONS = [("1 tsp", 5), ("1 tbsp", 15), ("1 katori", 150), ("1 cup", 200), ("1 glass", 250),
                    ("1 bowl", 100), ("1 plate", 200), ("1 piece", 30), ("1 slice", 30), ("1 scoop", 30),
                    ("1 handful", 30)]


class FoodUnitSerializer(serializers.ModelSerializer):
    id = serializers.IntegerField(required=False)

    class Meta:
        model = FoodUnit
        fields = ["id", "name", "grams"]

    def validate_name(self, v):
        v = " ".join(v.split())
        if not v:
            raise serializers.ValidationError("Name the unit.")
        return v[:40]


class FoodSerializer(serializers.ModelSerializer):
    units = FoodUnitSerializer(many=True, required=False)
    default_unit_name = serializers.CharField(write_only=True, required=False, allow_blank=True)
    default_unit = serializers.SerializerMethodField()
    swaps = serializers.PrimaryKeyRelatedField(many=True, queryset=Food.objects.all(), required=False)
    calories_match = serializers.BooleanField(read_only=True)
    calories_from_macros = serializers.FloatField(read_only=True)
    used_in = serializers.SerializerMethodField()
    used_tip = serializers.SerializerMethodField()
    mine = serializers.SerializerMethodField()

    class Meta:
        model = Food
        fields = ["id", "name", "brand", "diet", "group", "source", "source_note", "kcal", "protein", "carbs", "fat",
                  "fibre", "sodium_mg", "iron_mg", "calcium_mg", "potassium_mg", "units", "default_unit",
                  "default_unit_name", "default_quantity", "swaps", "calories_match", "calories_from_macros",
                  "used_in", "used_tip", "mine", "created_at", "updated_at"]
        read_only_fields = ["source"]

    def get_default_unit(self, obj):
        u = obj.default_unit
        return {"id": u.id, "name": u.name, "grams": u.grams} if u else {"id": None, "name": "g", "grams": 1}

    def get_used_in(self, obj):
        names = getattr(obj, "_used_in", None)
        if names is None:
            names = list(MealPlan.objects.filter(meals__options__items__food=obj, is_master=True).distinct()
                         .values_list("name", flat=True)[:10])
        return names

    def get_used_tip(self, obj):
        """"Cut · Eggetarian · Lunch, Dinner" per plan (the Used in pill's tooltip); filled by the list view."""
        return getattr(obj, "_used_tip", None) or []

    def get_mine(self, obj):
        return obj.owner_client_id is not None

    def validate_name(self, v):
        v = " ".join(v.split())
        if len(v) < 2:
            raise serializers.ValidationError("Enter the food name.")
        return v

    def validate_group(self, v):
        if v not in FOOD_GROUPS:
            raise serializers.ValidationError("Pick a group.")
        return v

    def validate(self, attrs):
        for f in ("protein", "carbs", "fat", "fibre"):
            if attrs.get(f, 0) and attrs[f] > 100:
                raise serializers.ValidationError({f: ["Per 100 g this can't be more than 100 g."]})
        p, c, f = (attrs.get(k, Decimal(0)) or Decimal(0) for k in ("protein", "carbs", "fat"))
        if p + c + f > 100:
            raise serializers.ValidationError({"protein": ["Protein, carbs and fat add up to more than 100 g."]})
        units = attrs.get("units")
        if units is not None:
            names = [u["name"].lower() for u in units]
            if len(names) != len(set(names)):
                raise serializers.ValidationError({"units": ["Two units have the same name."]})
            if len(units) > 12:
                raise serializers.ValidationError({"units": ["Up to 12 units."]})
        return attrs

    def _save_units(self, food, units, default_name):
        if units is not None:
            keep = []
            for u in units:
                obj = food.units.filter(id=u.get("id")).first() if u.get("id") else None
                if obj is None:
                    obj = food.units.filter(name=u["name"]).first() or FoodUnit(food=food)
                obj.name, obj.grams = u["name"], u["grams"]
                obj.save()
                keep.append(obj.id)
            food.units.exclude(id__in=keep).delete()
        if default_name is not None:
            food.default_unit = food.units.filter(name=default_name).first()
            food.save(update_fields=["default_unit"])

    def create(self, validated):
        units = validated.pop("units", None)
        default_name = validated.pop("default_unit_name", None)
        swaps = validated.pop("swaps", [])
        food = Food.objects.create(**validated)
        food.swaps.set([s for s in swaps if s.id != food.id])
        self._save_units(food, units, default_name)
        return food

    def update(self, food, validated):
        units = validated.pop("units", None)
        default_name = validated.pop("default_unit_name", None)
        swaps = validated.pop("swaps", None)
        for k, v in validated.items():
            setattr(food, k, v)
        food.save()
        if swaps is not None:
            food.swaps.set([s for s in swaps if s.id != food.id])
        self._save_units(food, units, default_name)
        return food


class FoodPickSerializer(serializers.ModelSerializer):
    """Light row for pickers and search."""

    units = FoodUnitSerializer(many=True, read_only=True)
    team = serializers.SerializerMethodField()
    mine = serializers.SerializerMethodField()
    default_unit = serializers.SerializerMethodField()

    class Meta:
        model = Food
        fields = ["id", "name", "brand", "diet", "group", "kcal", "protein", "carbs", "fat", "units", "default_unit",
                  "default_quantity", "team", "mine"]

    def get_team(self, obj):
        return obj.source in (Food.Source.TEAM, Food.Source.IMPORTED)

    def get_mine(self, obj):
        return obj.owner_client_id is not None

    def get_default_unit(self, obj):
        u = obj.default_unit
        return {"id": u.id, "name": u.name, "grams": u.grams} if u else {"id": None, "name": "g", "grams": 1}


# ---------------------------------------------------------------- meal plans
class SwapInSerializer(serializers.Serializer):
    """One swap of a planned food, as the editor sends it."""

    food = serializers.PrimaryKeyRelatedField(queryset=Food.objects.filter(owner_client__isnull=True))
    quantity = serializers.DecimalField(max_digits=7, decimal_places=2, min_value=Decimal("0.01"),
                                        max_value=Decimal("5000"))
    unit = serializers.PrimaryKeyRelatedField(queryset=FoodUnit.objects.all(), required=False, allow_null=True)

    def validate(self, attrs):
        u = attrs.get("unit")
        if u is not None and u.food_id != attrs["food"].id:
            raise serializers.ValidationError({"unit": [f"{u.name} is not a unit of {attrs['food'].name}."]})
        return attrs


class MealItemSerializer(serializers.ModelSerializer):
    """`swaps`: the foods the client may eat instead (this item's own list, else the food's library swaps), each
    with its amount, kcal / P / C / F and match %. Send `swaps` to replace the list; leave it out to keep it.
    `was` (a client's copy only): what the master has here when this food differs, e.g. "Moong dal (cooked),
    1 katori · 150 g", or "not in the master"; null when it is the same."""

    id = serializers.IntegerField(required=False)
    food_detail = FoodPickSerializer(source="food", read_only=True)
    grams = serializers.DecimalField(max_digits=9, decimal_places=2, read_only=True)
    macros = serializers.SerializerMethodField()
    swaps = SwapInSerializer(many=True, required=False, write_only=True)
    was = serializers.SerializerMethodField()

    class Meta:
        model = MealItem
        fields = ["id", "food", "food_detail", "quantity", "unit", "grams", "macros", "swaps", "was"]

    def get_macros(self, obj):
        return obj.macros()

    def get_was(self, obj):
        if not self.context.get("copy"):
            return None
        o = obj.origin
        if o is None:
            return "not in the master"
        if o.food_id == obj.food_id and o.quantity == obj.quantity and o.unit_id == obj.unit_id:
            return None
        return f"{o.food.name}, {amount_label(o.quantity, o.unit)}"

    def to_representation(self, obj):
        data = super().to_representation(obj)
        data["swaps"] = resolve(obj, self.context.setdefault("_foods", {}))
        return data


class MealOptionSerializer(serializers.ModelSerializer):
    id = serializers.IntegerField(required=False)
    items = MealItemSerializer(many=True, required=False)

    class Meta:
        model = MealOption
        fields = ["id", "name", "is_default", "items"]


class MealSerializer(serializers.ModelSerializer):
    id = serializers.IntegerField(required=False)
    options = MealOptionSerializer(many=True, required=False)
    weekday = serializers.IntegerField(read_only=True)  # null = every day; a client copy can have its own days

    class Meta:
        model = Meal
        fields = ["id", "name", "time", "kcal_target", "weekday", "options"]

    def validate(self, attrs):
        opts = attrs.get("options", [])
        if not opts:
            raise serializers.ValidationError("A meal needs at least one option.")
        return attrs


class MealPlanCardSerializer(serializers.ModelSerializer):
    clients = serializers.SerializerMethodField()
    client_count = serializers.IntegerField(read_only=True, source="n_clients", default=0)
    custom_count = serializers.IntegerField(read_only=True, source="n_custom", default=0)
    meal_count = serializers.IntegerField(read_only=True, source="n_meals", default=0)
    option_count = serializers.IntegerField(read_only=True, source="n_options", default=0)
    meal_names = serializers.SerializerMethodField()

    class Meta:
        model = MealPlan
        fields = ["id", "name", "diet", "kcal_target", "protein_g", "carbs_g", "fat_g", "fibre_g", "water_ml",
                  "status", "published_at", "has_unpublished_changes", "allow_swaps", "allow_search_any",
                  "allow_switch_options", "allow_off_plan", "client_count", "custom_count", "meal_count",
                  "option_count", "meal_names", "clients", "can_edit", "owner", "updated_at", "created_at"]
        read_only_fields = ["status", "published_at", "has_unpublished_changes"]

    can_edit = serializers.SerializerMethodField()
    owner = serializers.SerializerMethodField()

    def get_clients(self, obj):
        """Up to 3 avatars: only clients the viewer can see (a trainer sees their own)."""
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

    def get_meal_names(self, obj):
        names = getattr(obj, "_meal_names", None)
        return names if names is not None else list(obj.meals.filter(weekday__isnull=True).values_list("name", flat=True))

    def get_can_edit(self, obj):
        from .services import can_edit_meal_plan

        req = self.context.get("request")
        return bool(req and can_edit_meal_plan(req.user, obj))

    def get_owner(self, obj):
        """Who made it (card tag, builder line), as for programs (D-43)."""
        u = obj.created_by
        req = self.context.get("request")
        if u is None or u.is_admin:
            return {"kind": "gym", "name": "Gym", "label": "Gym plan"}
        if req and u.id == req.user.id:
            return {"kind": "you", "name": "You", "label": "Made by you"}
        return {"kind": "trainer", "name": u.first_name or u.full_name, "label": f"Made by {u.full_name}"}

    def validate_name(self, v):
        v = " ".join(v.split())
        if len(v) < 2:
            raise serializers.ValidationError("Enter a plan name.")
        return v

    def validate_kcal_target(self, v):
        if not 1200 <= v <= 4000:
            raise serializers.ValidationError("1,200 to 4,000 kcal.")
        return v


class MealPlanDetailSerializer(MealPlanCardSerializer):
    meals = MealSerializer(many=True, read_only=True)
    planned = serializers.SerializerMethodField()

    class Meta(MealPlanCardSerializer.Meta):
        fields = MealPlanCardSerializer.Meta.fields + ["meals", "planned"]

    def get_planned(self, obj):
        """'Meals add up to 2,140' — default options summed."""
        tot = {"kcal": 0, "protein": 0.0, "carbs": 0.0, "fat": 0.0}
        for meal in obj.meals.all():
            opt = next((o for o in meal.options.all() if o.is_default), None) or next(iter(meal.options.all()), None)
            if not opt:
                continue
            for it in opt.items.all():
                m = it.macros()
                for k in tot:
                    tot[k] += m[k]
        return {k: round(v, 1) if k != "kcal" else round(v) for k, v in tot.items()}


class MealStructureSerializer(serializers.Serializer):
    meals = MealSerializer(many=True)


class ClientMealDaySerializer(serializers.Serializer):
    """Client profile → Plans → Meal plan → Edit for X → Save: one weekday's meals of the client's copy."""

    weekday = serializers.IntegerField(min_value=0, max_value=6)
    every_day = serializers.BooleanField(default=False)
    meals = MealSerializer(many=True)

    def validate_meals(self, v):
        if len(v) > 12:
            raise serializers.ValidationError("Up to 12 meals a day.")
        for m in v:
            if not " ".join(str(m.get("name", "")).split()):
                raise serializers.ValidationError("Every meal needs a name.")
        return v


class FoodLogSerializer(serializers.ModelSerializer):
    class Meta:
        model = FoodLogEntry
        fields = ["id", "date", "logged_at", "meal_name", "meal", "food", "name", "quantity", "unit_name", "grams",
                  "kcal", "protein", "carbs", "fat", "source", "swapped_from", "reason", "other_time"]
        read_only_fields = ["date", "logged_at", "name", "kcal", "protein", "carbs", "fat", "grams", "source",
                            "swapped_from", "other_time"]


class LogFoodSerializer(serializers.Serializer):
    """Log food screen: + on a food, or Quick add."""

    meal_name = serializers.CharField(max_length=60)
    food = serializers.PrimaryKeyRelatedField(queryset=Food.objects.all(), required=False, allow_null=True)
    quantity = serializers.DecimalField(max_digits=7, decimal_places=2, min_value=Decimal("0.01"), default=1)
    unit = serializers.PrimaryKeyRelatedField(queryset=FoodUnit.objects.all(), required=False, allow_null=True)
    # quick add
    name = serializers.CharField(max_length=120, required=False, allow_blank=True)
    kcal = serializers.IntegerField(min_value=1, max_value=10000, required=False)
    protein = serializers.DecimalField(max_digits=6, decimal_places=1, min_value=0, required=False)
    carbs = serializers.DecimalField(max_digits=6, decimal_places=1, min_value=0, required=False)
    fat = serializers.DecimalField(max_digits=6, decimal_places=1, min_value=0, required=False)
    unit_name = serializers.CharField(max_length=40, required=False, allow_blank=True)
    off_plan = serializers.BooleanField(required=False, default=False)
    reason = serializers.ChoiceField(choices=["", "Ate out", "Party", "Travelling"], required=False, default="")
    # Add to → Other time: meal_name is the name the client gave ("Evening chai"), logged_at the time they picked
    other_time = serializers.BooleanField(required=False, default=False)

    def validate(self, attrs):
        if not attrs.get("food") and not attrs.get("kcal"):
            raise serializers.ValidationError({"kcal": ["Enter the calories first — Protein, carbs and fat are "
                                                        "optional."]})
        unit = attrs.get("unit")
        if unit and attrs.get("food") and unit.food_id != attrs["food"].id:
            raise serializers.ValidationError({"unit": ["That unit belongs to another food."]})
        return attrs


class CustomFoodSerializer(serializers.Serializer):
    """Log food → Create custom food: values for one serving."""

    name = serializers.CharField(max_length=120)
    serving = serializers.CharField(max_length=40)
    kcal = serializers.DecimalField(max_digits=7, decimal_places=1, min_value=1, max_value=5000)
    protein = serializers.DecimalField(max_digits=6, decimal_places=1, min_value=0, max_value=500, default=0)
    carbs = serializers.DecimalField(max_digits=6, decimal_places=1, min_value=0, max_value=500, default=0)
    fat = serializers.DecimalField(max_digits=6, decimal_places=1, min_value=0, max_value=500, default=0)

    def validate_name(self, v):
        v = " ".join(v.split())
        if len(v) < 2:
            raise serializers.ValidationError("Enter the food name.")
        return v

    def validate_serving(self, v):
        v = " ".join(v.split())
        if not v:
            raise serializers.ValidationError("Enter the serving, e.g. 1 katori.")
        return v


DIETS = Diet
