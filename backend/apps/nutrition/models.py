import uuid
from decimal import Decimal

from django.conf import settings
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models
from django.utils import timezone

from apps.common.models import SoftDeleteModel, TimeStampedModel


class Diet(models.TextChoices):
    VEG = "veg", "Vegetarian"
    EGG = "egg", "Eggetarian"
    NONVEG = "nonveg", "Non-veg"
    VEGAN = "vegan", "Vegan"


FOOD_GROUPS = ["protein", "carbs", "fats", "veg", "fruits", "dairy", "indian", "beverages", "other"]

NUM = dict(max_digits=7, decimal_places=2, validators=[MinValueValidator(0)])


class Food(SoftDeleteModel):
    """Every number is stored per 100 g (ml counts as g), whatever the person typed in."""

    class Source(models.TextChoices):
        BUILTIN = "builtin", "Built-in"
        TEAM = "team", "Made by your team"
        IMPORTED = "imported", "Imported"
        CLIENT = "client", "Client's own"

    name = models.CharField(max_length=120, db_index=True)
    brand = models.CharField(max_length=80, blank=True, default="")
    diet = models.CharField(max_length=6, choices=Diet.choices, default=Diet.VEG, db_index=True)
    group = models.CharField(max_length=30, default="other", db_index=True)
    source = models.CharField(max_length=10, choices=Source.choices, default=Source.TEAM, db_index=True)
    source_note = models.CharField(max_length=40, blank=True, default="")  # "IFCT"
    owner_client = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.CASCADE,
                                     related_name="own_foods")  # client "My foods"
    kcal = models.DecimalField(max_digits=7, decimal_places=1, validators=[MinValueValidator(0),
                                                                           MaxValueValidator(900)])
    protein = models.DecimalField(**NUM, default=Decimal("0"))
    carbs = models.DecimalField(**NUM, default=Decimal("0"))
    fat = models.DecimalField(**NUM, default=Decimal("0"))
    fibre = models.DecimalField(**NUM, default=Decimal("0"))
    sodium_mg = models.DecimalField(**NUM, null=True, blank=True)
    iron_mg = models.DecimalField(**NUM, null=True, blank=True)
    calcium_mg = models.DecimalField(**NUM, null=True, blank=True)
    potassium_mg = models.DecimalField(**NUM, null=True, blank=True)
    default_unit = models.ForeignKey("FoodUnit", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    default_quantity = models.DecimalField(max_digits=6, decimal_places=2, default=Decimal("1"))
    swaps = models.ManyToManyField("self", blank=True, symmetrical=False, related_name="swapped_by")
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL,
                                   related_name="+")

    class Meta:
        ordering = ["name"]
        indexes = [models.Index(fields=["group", "diet"])]

    def __str__(self):
        return self.name

    def per_grams(self, grams):
        f = Decimal(grams) / Decimal(100)
        return {
            "kcal": round(float(self.kcal * f)),
            "protein": round(float(self.protein * f), 1),
            "carbs": round(float(self.carbs * f), 1),
            "fat": round(float(self.fat * f), 1),
        }

    @property
    def calories_from_macros(self):
        return float(4 * self.protein + 4 * self.carbs + 9 * self.fat)

    @property
    def calories_match(self):
        """Design: badge "Calories match" when typed kcal ≈ 4P + 4C + 9F."""
        calc = self.calories_from_macros
        return abs(calc - float(self.kcal)) <= max(15, 0.1 * float(self.kcal))


class FoodUnit(models.Model):
    """Serving units of one food. 1 g is always implied and never stored."""

    food = models.ForeignKey(Food, on_delete=models.CASCADE, related_name="units")
    name = models.CharField(max_length=40)  # "1 katori"
    grams = models.DecimalField(max_digits=7, decimal_places=2, validators=[MinValueValidator(Decimal("0.1"))])

    class Meta:
        ordering = ["grams"]
        constraints = [models.UniqueConstraint(fields=["food", "name"], name="uniq_food_unit_name")]


class MealPlan(SoftDeleteModel):
    class Status(models.TextChoices):
        DRAFT = "draft", "Draft"
        PUBLISHED = "published", "Published"

    name = models.CharField(max_length=120)
    diet = models.CharField(max_length=6, choices=Diet.choices, default=Diet.VEG)
    kcal_target = models.PositiveIntegerField(default=2000, validators=[MinValueValidator(1200),
                                                                        MaxValueValidator(4000)])
    protein_g = models.PositiveSmallIntegerField(default=120)
    carbs_g = models.PositiveSmallIntegerField(default=200)
    fat_g = models.PositiveSmallIntegerField(default=60)
    fibre_g = models.PositiveSmallIntegerField(default=30)
    water_ml = models.PositiveIntegerField(default=3000)
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.DRAFT)
    published_at = models.DateTimeField(null=True, blank=True)
    has_unpublished_changes = models.BooleanField(default=False)
    allow_swaps = models.BooleanField(default=True)  # within the approved list
    allow_search_any = models.BooleanField(default=False)
    allow_switch_options = models.BooleanField(default=True)
    allow_off_plan = models.BooleanField(default=True)  # flagged to coach
    # A client's own copy (Client profile → Plans → Meal plan → Edit for X) is not a library plan: it hangs off
    # MealPlanAssignment.custom_plan and points back at its master. The library only lists masters.
    is_master = models.BooleanField(default=True, db_index=True)
    master = models.ForeignKey("self", null=True, blank=True, on_delete=models.SET_NULL, related_name="copies")
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL,
                                   related_name="+")

    class Meta:
        ordering = ["-updated_at"]

    def __str__(self):
        return self.name


class Meal(models.Model):
    plan = models.ForeignKey(MealPlan, on_delete=models.CASCADE, related_name="meals")
    name = models.CharField(max_length=60)
    time = models.TimeField()
    kcal_target = models.PositiveIntegerField(default=0)
    order = models.PositiveSmallIntegerField(default=0)
    # null = every day. A client copy can give one weekday (0 = Monday) its own meals: when a plan has meals
    # for that weekday, that day shows only those; other days show the every-day meals (see `meals_on`).
    weekday = models.PositiveSmallIntegerField(null=True, blank=True, validators=[MaxValueValidator(6)])

    class Meta:
        ordering = ["time", "order"]


def meals_on(plan, weekday):
    """The meals of `plan` on a weekday (0 = Monday): that day's own meals, else the every-day ones."""
    own = plan.meals.filter(weekday=weekday)
    return own if own.exists() else plan.meals.filter(weekday__isnull=True)


class MealOption(models.Model):
    meal = models.ForeignKey(Meal, on_delete=models.CASCADE, related_name="options")
    name = models.CharField(max_length=40)  # "Veg", "Eggs", "Eating out"
    is_default = models.BooleanField(default=False)
    order = models.PositiveSmallIntegerField(default=0)

    class Meta:
        ordering = ["order"]


class MealItem(models.Model):
    option = models.ForeignKey(MealOption, on_delete=models.CASCADE, related_name="items")
    food = models.ForeignKey(Food, on_delete=models.PROTECT, related_name="meal_items")
    quantity = models.DecimalField(max_digits=7, decimal_places=2, validators=[MinValueValidator(Decimal("0.01"))])
    unit = models.ForeignKey(FoodUnit, null=True, blank=True, on_delete=models.SET_NULL, related_name="+")  # null = g
    order = models.PositiveSmallIntegerField(default=0)

    class Meta:
        ordering = ["order"]

    @property
    def grams(self):
        return self.quantity * (self.unit.grams if self.unit else Decimal(1))

    def macros(self):
        return self.food.per_grams(self.grams)


class MealPlanAssignment(TimeStampedModel):
    client = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
                               related_name="meal_plan_assignments")
    plan = models.ForeignKey(MealPlan, on_delete=models.PROTECT, related_name="assignments")
    version_note = models.TextField(blank=True, default="", max_length=1000)  # custom version for this client
    # The client's own copy of `plan` (Edit for X): foods, portions, meal names and per-weekday meals. null = the
    # client follows the master as it is. The master is never changed by it.
    custom_plan = models.ForeignKey(MealPlan, null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    start_date = models.DateField(default=timezone.localdate)
    end_date = models.DateField(null=True, blank=True)
    status = models.CharField(max_length=10, default="active", db_index=True,
                              choices=[("up_next", "Up next"), ("active", "Active"), ("ended", "Ended")])
    assigned_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="+")

    class Meta:
        indexes = [models.Index(fields=["client", "status"])]

    @property
    def followed(self):
        """The plan the client actually eats from: their own copy, else the master."""
        return self.custom_plan or self.plan


def meal_photo_path(instance, filename):
    ext = (filename.rsplit(".", 1)[-1] if "." in filename else "jpg").lower()[:5]
    return f"meals/{instance.client_id}/{uuid.uuid4().hex}.{ext}"


class MealDayState(TimeStampedModel):
    """A client's day for one planned meal: logged / skipped, today's portions and swaps.
    Swaps and portions only ever apply to that one day (design rule)."""

    class Status(models.TextChoices):
        LOGGED = "logged", "Logged"
        SKIPPED = "skipped", "Skipped"

    client = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="meal_days")
    date = models.DateField(db_index=True)
    meal = models.ForeignKey(Meal, on_delete=models.CASCADE, related_name="+")
    option = models.ForeignKey(MealOption, null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    status = models.CharField(max_length=8, choices=Status.choices, blank=True, default="")
    portions = models.JSONField(default=dict, blank=True)  # {meal_item_id: quantity}
    swaps = models.JSONField(default=dict, blank=True)  # {meal_item_id: {"food": id, "quantity": q}}
    logged_at = models.DateTimeField(null=True, blank=True)
    photo = models.ImageField(upload_to=meal_photo_path, null=True, blank=True)  # optional, sent with "Mark as eaten"

    class Meta:
        constraints = [models.UniqueConstraint(fields=["client", "date", "meal"], name="uniq_meal_day")]


class FoodLogEntry(TimeStampedModel):
    """Everything eaten, one row per food. Big table: always read by (client, date)."""

    class Source(models.TextChoices):
        PLAN = "plan", "From your plan"
        OFF_PLAN = "off_plan", "Outside the plan"
        QUICK_ADD = "quick_add", "Quick add"

    client = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="food_logs")
    date = models.DateField()
    logged_at = models.DateTimeField(default=timezone.now)
    meal_name = models.CharField(max_length=60)  # "Breakfast"
    meal = models.ForeignKey(Meal, null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    food = models.ForeignKey(Food, null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    name = models.CharField(max_length=120)  # snapshot, survives food edits
    quantity = models.DecimalField(max_digits=7, decimal_places=2, default=Decimal("1"))
    unit_name = models.CharField(max_length=40, default="g")
    grams = models.DecimalField(max_digits=8, decimal_places=2, null=True, blank=True)
    kcal = models.PositiveIntegerField(validators=[MaxValueValidator(10000)])
    protein = models.DecimalField(max_digits=6, decimal_places=1, default=Decimal("0"))
    carbs = models.DecimalField(max_digits=6, decimal_places=1, default=Decimal("0"))
    fat = models.DecimalField(max_digits=6, decimal_places=1, default=Decimal("0"))
    source = models.CharField(max_length=10, choices=Source.choices, default=Source.PLAN)
    swapped_from = models.CharField(max_length=120, blank=True, default="")
    reason = models.CharField(max_length=20, blank=True, default="")  # off-plan: "Ate out", "Party", "Travelling"
    # Log food → Add to → Other time: eaten outside the meal times, so it sits in the food log at its own time
    # under its own name (meal_name) and never inside a meal card. Always off-plan.
    other_time = models.BooleanField(default=False)

    class Meta:
        ordering = ["logged_at"]
        indexes = [models.Index(fields=["client", "date"])]


class WaterLog(models.Model):
    client = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="water_logs")
    date = models.DateField()
    ml = models.PositiveIntegerField(default=0, validators=[MaxValueValidator(10000)])
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["client", "date"], name="uniq_water_day")]


class FoodImportJob(TimeStampedModel):
    class Status(models.TextChoices):
        CHECKED = "checked", "Ready to import"
        IMPORTED = "imported", "Imported"
        FAILED = "failed", "Failed"

    file = models.FileField(upload_to="imports/")
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.CHECKED)
    rows = models.JSONField(default=list)
    summary = models.JSONField(default=dict)
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="+")
