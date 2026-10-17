from datetime import timedelta
from decimal import Decimal

from django.db import transaction
from django.db.models import Count, Q
from django.http import HttpResponse
from django.shortcuts import get_object_or_404
from django.utils import timezone
from django.utils.dateparse import parse_date
from drf_spectacular.utils import extend_schema
from rest_framework import mixins, serializers, status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.activity.services import log as activity_log
from apps.clients.services import get_visible_client, visible_clients
from apps.common.mixins import SoftDeleteViewMixin
from apps.common.permissions import HasTrainerPermission, IsClient, IsStaff
from apps.common.utils import data_url_file, sync_day, sync_time

from . import importer, services
from .models import (
    FOOD_GROUPS,
    Diet,
    Food,
    FoodImportJob,
    FoodLogEntry,
    FoodUnit,
    Meal,
    MealDayState,
    MealItem,
    MealPlan,
    MealPlanAssignment,
    meals_on,
)
from .serializers import (
    UNIT_SUGGESTIONS,
    ClientMealDaySerializer,
    CustomFoodSerializer,
    FoodLogSerializer,
    FoodPickSerializer,
    FoodSerializer,
    LogFoodSerializer,
    MealPlanCardSerializer,
    MealPlanDetailSerializer,
    MealStructureSerializer,
    match_percent,
    same_kcal_grams,
)


def _staff_or_404(user, client_id):
    try:
        return get_visible_client(user, client_id)
    except Exception:
        from django.http import Http404

        raise Http404


# ---------------------------------------------------------------- foods
class FoodViewSet(SoftDeleteViewMixin, viewsets.ModelViewSet):
    """Food library (staff). Clients search foods through /me/foods/."""

    serializer_class = FoodSerializer
    permission_classes = [IsStaff, HasTrainerPermission]
    required_permissions = {"create": "nutrition.foods", "partial_update": "nutrition.foods",
                            "update": "nutrition.foods", "destroy": "nutrition.foods",
                            "duplicate": "nutrition.foods", "import_check": "nutrition.foods",
                            "import_run": "nutrition.foods"}
    search_fields = ["name", "brand"]
    ordering_fields = ["name", "kcal", "protein", "carbs", "fat", "updated_at"]
    ordering = ["name"]
    http_method_names = ["get", "post", "patch", "delete"]

    def get_queryset(self):
        qs = Food.objects.filter(owner_client__isnull=True).select_related("default_unit").prefetch_related(
            "units", "swaps")
        p = self.request.query_params
        g = p.get("group")
        if g == "mine":
            qs = qs.filter(source=Food.Source.TEAM)
        elif g in FOOD_GROUPS:
            qs = qs.filter(group=g)
        if p.get("diet"):
            qs = qs.filter(diet=p["diet"])
        return qs

    @action(detail=False)
    def counts(self, request):
        qs = Food.objects.filter(owner_client__isnull=True)
        if request.query_params.get("diet"):
            qs = qs.filter(diet=request.query_params["diet"])
        by = dict(qs.values_list("group").annotate(n=Count("id")))
        return Response({"all": qs.count(), "mine": qs.filter(source=Food.Source.TEAM).count(),
                         **{g: by.get(g, 0) for g in FOOD_GROUPS}, "unit_suggestions": UNIT_SUGGESTIONS})

    def list(self, request, *args, **kwargs):
        resp = super().list(request, *args, **kwargs)
        return resp

    def perform_create(self, serializer):
        food = serializer.save(source=Food.Source.TEAM, created_by=self.request.user)
        activity_log("added a food", "plan", actor=self.request.user, target=food, target_label=food.name)

    def perform_update(self, serializer):
        food = serializer.save()
        activity_log("edited a food", "plan", actor=self.request.user, target=food, target_label=food.name)

    @action(detail=True, url_path="delete-preview")
    def delete_preview(self, request, pk=None):
        food = self.get_object()
        return Response({"plans": MealPlan.objects.filter(meals__options__items__food=food).distinct().count()})

    @action(detail=True, methods=["post"])
    def duplicate(self, request, pk=None):
        src = self.get_object()
        data = FoodSerializer(src).data
        data["name"] = f"{src.name} (copy)"[:120]
        data["units"] = [{"name": u["name"], "grams": u["grams"]} for u in data["units"]]
        data["default_unit_name"] = data["default_unit"]["name"] if data["default_unit"]["id"] else ""
        s = FoodSerializer(data=data)
        s.is_valid(raise_exception=True)
        food = s.save(source=Food.Source.TEAM, created_by=request.user)
        return Response(FoodSerializer(food).data, status=201)

    @action(detail=True, url_path="used-in")
    def used_in(self, request, pk=None):
        food = self.get_object()
        rows = (MealItem.objects.filter(food=food).select_related("option__meal__plan")
                .values_list("option__meal__plan_id", "option__meal__plan__name", "option__meal__name",
                             "option__name").distinct())
        return Response([{"plan": str(p), "plan_name": pn, "meal": m, "option": o} for p, pn, m, o in rows])

    @action(detail=True, url_path="swap-options")
    def swap_options(self, request, pk=None):
        """'Add alternative' list: same group (or all), top 6 by match %."""
        food = self.get_object()
        qs = Food.objects.filter(owner_client__isnull=True).exclude(id=food.id)
        if request.query_params.get("scope", "group") == "group":
            qs = qs.filter(group=food.group)
        grams = request.query_params.get("grams") or 100
        try:
            grams = float(grams)
        except ValueError:
            grams = 100
        scored = sorted(((match_percent(food, f), f) for f in qs[:500]), key=lambda t: -t[0])[:6]
        return Response([{**FoodPickSerializer(f).data, "match": m, "same_kcal_grams": same_kcal_grams(food, grams, f)}
                         for m, f in scored])

    # -------- Excel import
    @action(detail=False, methods=["post"], url_path="import/check", parser_classes=[MultiPartParser, FormParser])
    def import_check(self, request):
        f = request.FILES.get("file")
        if not f:
            raise serializers.ValidationError({"file": ["Choose a file first — Excel or CSV"]})
        if f.size > 5 * 1024 * 1024:
            raise serializers.ValidationError({"file": ["The file is over 5 MB."]})
        try:
            job = importer.check(f, user=request.user)
        except ValueError as e:
            raise serializers.ValidationError({"file": [str(e)]})
        return Response({"id": str(job.id), "summary": job.summary, "rows": job.rows})

    @action(detail=False, methods=["post"], url_path=r"import/(?P<job_id>[0-9a-f-]+)/run",
            parser_classes=[JSONParser])
    def import_run(self, request, job_id=None):
        job = get_object_or_404(FoodImportJob, id=job_id, created_by=request.user)
        d = request.data
        if d.get("duplicates", "skip") not in ("skip", "update", "new"):
            raise serializers.ValidationError({"duplicates": ["Pick skip, update or new."]})
        try:
            c, u, s = importer.run(job, duplicates=d.get("duplicates", "skip"), kcal_choice=d.get("kcal_choice"),
                                   eggs_eggetarian=d.get("eggs_eggetarian", True), group_map=d.get("group_map"),
                                   diet_map=d.get("diet_map"), user=request.user)
        except ValueError as e:
            raise serializers.ValidationError(str(e))
        activity_log("imported foods", "plan", actor=request.user, target_label=f"{c} foods",
                     meta={"created": c, "updated": u})
        return Response({"created": c, "updated": u, "skipped": s})

    @action(detail=False, methods=["post"], url_path=r"import/(?P<job_id>[0-9a-f-]+)/undo")
    def import_undo(self, request, job_id=None):
        job = get_object_or_404(FoodImportJob, id=job_id, created_by=request.user,
                                status=FoodImportJob.Status.IMPORTED)
        importer.undo(job)
        return Response(status=204)

    @action(detail=False, url_path="import/template")
    def import_template(self, request):
        resp = HttpResponse(importer.template_xlsx(),
                            content_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
        resp["Content-Disposition"] = 'attachment; filename="food-import-template.xlsx"'
        return resp


# ---------------------------------------------------------------- meal plans
class MealPlanViewSet(SoftDeleteViewMixin, viewsets.ModelViewSet):
    permission_classes = [IsStaff, HasTrainerPermission]
    search_fields = ["name"]
    ordering = ["-updated_at"]
    http_method_names = ["get", "post", "patch", "put", "delete"]

    def check_permissions(self, request):
        super().check_permissions(request)
        u = request.user
        if u.is_trainer and request.method not in ("GET", "HEAD", "OPTIONS"):
            needed = "nutrition.meal_plans" if self.action in ("assign", "version_note", "reset_client",
                                                               "remove_client") else "training.edit_templates"
            if self.action in ("create", "duplicate"):
                needed = "nutrition.meal_plans"
            if not u.trainer_profile.has_perm(needed):
                raise PermissionDenied("Your access does not include this. Ask Vimal for more access.")

    def get_queryset(self):
        custom = ~Q(assignments__version_note="") | Q(assignments__custom_plan__isnull=False)
        qs = MealPlan.objects.filter(is_master=True).annotate(  # client copies never show in the library
            n_clients=Count("assignments", filter=Q(assignments__status="active"), distinct=True),
            n_custom=Count("assignments", filter=Q(assignments__status="active") & custom, distinct=True),
            n_meals=Count("meals", distinct=True),
            n_options=Count("meals__options", distinct=True),
        )
        if self.request.query_params.get("diet"):
            qs = qs.filter(diet=self.request.query_params["diet"])
        if self.action == "retrieve":
            qs = qs.prefetch_related("meals__options__items__food__units", "meals__options__items__unit",
                                     "meals__options__items__food__default_unit")
        return qs

    def get_serializer_class(self):
        return MealPlanDetailSerializer if self.action in ("retrieve", "structure") else MealPlanCardSerializer

    @action(detail=False)
    def counts(self, request):
        by = dict(MealPlan.objects.filter(is_master=True).values_list("diet").annotate(n=Count("id")))
        return Response({"all": sum(by.values()), **by})

    def create(self, request, *args, **kwargs):
        s = MealPlanCardSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        p = services.new_plan(name=d["name"], diet=d.get("diet", "veg"), kcal_target=d.get("kcal_target", 2000),
                              actor=request.user)
        activity_log("created a meal plan", "plan", actor=request.user, target=p, target_label=p.name)
        return Response(MealPlanDetailSerializer(self.get_queryset().get(id=p.id)).data, status=201)

    def perform_update(self, serializer):
        p = serializer.save()
        if p.status == MealPlan.Status.PUBLISHED:
            p.has_unpublished_changes = True
            p.save(update_fields=["has_unpublished_changes"])

    def perform_destroy(self, instance):
        with transaction.atomic():
            instance.soft_delete()
            MealPlanAssignment.objects.filter(plan=instance, status="active").update(
                status="ended", end_date=timezone.localdate())
        activity_log("deleted a meal plan", "plan", actor=self.request.user, target=instance,
                     target_label=instance.name)

    @extend_schema(request=MealStructureSerializer)
    @action(detail=True, methods=["put"])
    def structure(self, request, pk=None):
        plan = self.get_object()
        s = MealStructureSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        services.sync_meals(plan, s.validated_data["meals"])
        return Response(MealPlanDetailSerializer(self.get_queryset().get(id=plan.id)).data)

    @action(detail=True, methods=["post"])
    def duplicate(self, request, pk=None):
        p = services.duplicate_plan(self.get_object(), actor=request.user)
        return Response(MealPlanCardSerializer(self.get_queryset().get(id=p.id)).data, status=201)

    @action(detail=True, url_path="publish-preview")
    def publish_preview(self, request, pk=None):
        p = self.get_object()
        return Response({"clients": p.n_clients, "custom": p.n_custom})

    @action(detail=True, methods=["post"])
    def publish(self, request, pk=None):
        n = services.publish(self.get_object(), actor=request.user)
        return Response({"sent_to": n})

    @action(detail=True)
    def clients(self, request, pk=None):
        p = self.get_object()
        visible = set(visible_clients(request.user).values_list("id", flat=True))
        rows = MealPlanAssignment.objects.filter(plan=p, status="active").select_related(
            "client__client_profile__trainer")
        return Response([{"assignment": a.id, "id": str(a.client_id), "full_name": a.client.full_name,
                          "initials": a.client.initials, "avatar_color": a.client.avatar_color,
                          "custom": bool(a.version_note or a.custom_plan_id), "version_note": a.version_note,
                          "trainer": a.client.client_profile.trainer.full_name
                          if a.client.client_profile.trainer else None}
                         for a in rows if a.client_id in visible])

    @action(detail=True, methods=["post"])
    def assign(self, request, pk=None):
        ids = request.data.get("clients")
        if not isinstance(ids, list):
            raise serializers.ValidationError({"clients": ["Send a list of clients."]})
        added, removed = services.set_plan_clients(self.get_object(), ids, actor=request.user)
        return Response({"added": added, "removed": removed})

    def _assignment(self, pk, client_id):
        a = MealPlanAssignment.objects.filter(plan_id=pk, client_id=client_id, status="active").first()
        if a is None or not visible_clients(self.request.user).filter(id=client_id).exists():
            from django.http import Http404

            raise Http404
        return a

    @action(detail=True, methods=["put"], url_path=r"clients/(?P<client_id>[0-9a-f-]+)/version-note")
    def version_note(self, request, pk=None, client_id=None):
        a = self._assignment(pk, client_id)
        note = (request.data.get("version_note") or "").strip()
        if len(note) > 1000:
            raise serializers.ValidationError({"version_note": ["Keep it under 1,000 characters."]})
        a.version_note = note
        a.save(update_fields=["version_note", "updated_at"])
        return Response({"version_note": a.version_note, "custom": bool(note)})

    @action(detail=True, methods=["post"], url_path=r"clients/(?P<client_id>[0-9a-f-]+)/reset")
    def reset_client(self, request, pk=None, client_id=None):
        a = self._assignment(pk, client_id)
        return Response({"previous_note": services.reset_client_copy(a, actor=request.user)})

    @action(detail=True, methods=["post"], url_path=r"clients/(?P<client_id>[0-9a-f-]+)/remove")
    def remove_client(self, request, pk=None, client_id=None):
        a = self._assignment(pk, client_id)
        a.status = "ended"
        a.end_date = timezone.localdate()
        a.save(update_fields=["status", "end_date", "updated_at"])
        return Response(status=204)


class ClientMealPlanViewSet(viewsets.ViewSet):
    """Client profile → Plans → Meal plan slot: current, Up next and history; assign one plan; end it."""

    permission_classes = [IsStaff]

    def _client(self):
        return _staff_or_404(self.request.user, self.kwargs["client_pk"])

    def _check_write(self, request):
        if request.user.is_trainer and not request.user.trainer_profile.has_perm("nutrition.meal_plans"):
            raise PermissionDenied("Your access does not include meal plans. Ask Vimal for more access.")

    @staticmethod
    def row(a):
        p = a.plan
        f = a.followed
        return {"id": a.id, "plan": p.id, "plan_name": p.name, "diet": p.diet, "diet_label": p.get_diet_display(),
                "kcal": p.kcal_target, "protein_g": p.protein_g, "carbs_g": p.carbs_g, "fat_g": p.fat_g,
                "meals": meals_on(f, timezone.localdate().weekday()).count(), "version_note": a.version_note,
                "custom": bool(a.version_note or a.custom_plan_id), "copy": a.custom_plan_id,
                "start_date": a.start_date, "end_date": a.end_date, "status": a.status,
                "assigned_by": a.assigned_by.full_name if a.assigned_by else None}

    def list(self, request, client_pk=None):
        rows = list(MealPlanAssignment.objects.filter(client=self._client())
                    .select_related("plan", "custom_plan", "assigned_by")
                    .order_by("-start_date", "-created_at"))
        return Response({k: [self.row(a) for a in rows if a.status == s]
                         for k, s in (("current", "active"), ("up_next", "up_next"), ("history", "ended"))})

    def create(self, request, client_pk=None):
        self._check_write(request)
        client = self._client()
        plan = MealPlan.objects.filter(id=request.data.get("plan"), is_master=True).first()
        start = parse_date(str(request.data.get("start_date") or ""))
        a = services.assign_plan_to_client(client, plan, actor=request.user, start_date=start,
                                           notify_client=request.data.get("notify", True) is not False)
        return Response(self.row(a), status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["post"])
    def end(self, request, client_pk=None, pk=None):
        self._check_write(request)
        a = get_object_or_404(MealPlanAssignment.objects.select_related("plan", "client"), id=pk,
                              client=self._client(), status__in=["active", "up_next"])
        if a.status == "up_next":  # not started yet: nothing to keep in history
            a.delete()
            return Response(status=status.HTTP_204_NO_CONTENT)
        services.end_client_plan(a, actor=request.user)
        return Response(self.row(a))

    def _mine(self, pk):
        return get_object_or_404(MealPlanAssignment.objects.select_related("plan", "custom_plan", "client"), id=pk,
                                 client=self._client(), status__in=["active", "up_next"])

    def _meals(self, a):
        plan = (MealPlan.all_objects.filter(id=a.followed.id)
                .prefetch_related("meals__options__items__food__units", "meals__options__items__unit",
                                  "meals__options__items__food__default_unit").get())
        return {**MealPlanDetailSerializer(plan).data, "id": a.plan_id, "copy": a.custom_plan_id,
                "custom": a.custom_plan_id is not None,
                "own_days": sorted({m.weekday for m in plan.meals.all() if m.weekday is not None})}

    @extend_schema(request=ClientMealDaySerializer)
    @action(detail=True, methods=["get", "put"])
    def meals(self, request, client_pk=None, pk=None):
        """GET: the meals the client follows (their copy, else the master), each with `weekday` (null = every
        day). PUT {weekday, every_day, meals}: Edit for X → Save. Makes the client's own copy on the first save;
        the master is not changed."""
        a = self._mine(pk)
        if request.method == "PUT":
            self._check_write(request)
            s = ClientMealDaySerializer(data=request.data)
            s.is_valid(raise_exception=True)
            d = s.validated_data
            services.save_client_day(a, weekday=d["weekday"], every_day=d["every_day"], meals_data=d["meals"],
                                     actor=request.user)
            a.refresh_from_db()
        return Response(self._meals(a))

    @action(detail=True, methods=["post"], url_path="reset")
    def reset(self, request, client_pk=None, pk=None):
        """Reset to master: drops the client's copy (and the old version note)."""
        self._check_write(request)
        a = self._mine(pk)
        services.reset_client_copy(a, actor=request.user)
        a.refresh_from_db()
        return Response(self.row(a))


class FoodPickerView(APIView):
    """Builder → Add food: team foods first, grouped."""

    permission_classes = [IsStaff]

    def get(self, request):
        qs = Food.objects.filter(owner_client__isnull=True).prefetch_related("units").select_related("default_unit")
        q = request.query_params.get("search")
        if q:
            qs = qs.filter(name__icontains=q)
        g = request.query_params.get("group")
        if g in FOOD_GROUPS:
            qs = qs.filter(group=g)
        qs = qs.order_by("source", "name")[:200]
        return Response(FoodPickSerializer(qs, many=True).data)


# ---------------------------------------------------------------- client food (staff view)
class ClientFoodLogView(APIView):
    """Client profile → Logs → Meals: one day (`?date=`), or one page of days (`?range=&page=`)."""

    permission_classes = [IsStaff, HasTrainerPermission]
    required_permission = "nutrition.food_logs"

    def get(self, request, client_pk):
        client = _staff_or_404(request.user, client_pk)
        day = parse_date(request.query_params.get("date") or "")
        if day:
            return Response(services.day_view(client, day, request))
        return Response(services.staff_food_log(client, request.query_params))


# ---------------------------------------------------------------- client app
class MyFoodView(APIView):
    """Food tab (combined meal plan + nutrition): GET ?date=YYYY-MM-DD."""

    permission_classes = [IsClient]

    def get(self, request):
        day = parse_date(request.query_params.get("date") or "") or timezone.localdate()
        return Response(services.day_view(request.user, day, request))


class MyMealActionView(APIView):
    """POST /me/food/meals/<meal_id>/<op>/  op = eat | unlog | skip | unskip | portions | swap | option"""

    permission_classes = [IsClient]

    def post(self, request, meal_id, op):
        mp = services._active_plan(request.user, timezone.localdate())
        if mp is None:
            raise serializers.ValidationError("You don't have a meal plan yet.")
        meal = get_object_or_404(Meal, id=meal_id, plan=mp.followed)
        day = sync_day(request.data.get("date"))
        today = timezone.localdate()
        if op in ("portions", "swap", "option") and day < today - timedelta(days=1):
            raise serializers.ValidationError("Swaps and portions only apply to today.")
        plan = mp.followed
        if op == "eat":
            photo = request.data.get("photo")  # optional: a picture of the meal, as a data URL (works offline)
            services.mark_eaten(request.user, meal, day,
                                photo=data_url_file(photo, f"meal-{meal.id}") if photo else None)
            _log_meal(request.user, meal, day, f"logged {meal.name.lower()}")
        elif op in ("unlog", "unskip"):
            services.unmark(request.user, meal, day)
        elif op == "photo":
            # Change or remove the photo of a meal already logged (data URL, or null to remove).
            st = MealDayState.objects.filter(client=request.user, date=day, meal=meal,
                                             status=MealDayState.Status.LOGGED).first()
            if st is None:
                raise serializers.ValidationError("Mark the meal as eaten first.")
            photo = request.data.get("photo")
            if st.photo:
                st.photo.delete(save=False)
            st.photo = data_url_file(photo, f"meal-{meal.id}") if photo else None
            st.save(update_fields=["photo", "updated_at"])
        elif op == "skip":
            services.skip(request.user, meal, day)
            activity_log(f"skipped {meal.name.lower()}", "meal", actor=request.user, client=request.user,
                         target_label=meal.name)
        elif op == "portions":
            st, _ = MealDayState.objects.get_or_create(client=request.user, date=day, meal=meal)
            portions = request.data.get("portions") or {}
            valid = set(MealItem.objects.filter(option__meal=meal).values_list("id", flat=True))
            clean = {}
            for k, v in portions.items():
                try:
                    if int(k) in valid and 0 < float(v) <= 5000:
                        clean[str(int(k))] = float(v)
                except (TypeError, ValueError):
                    continue
            st.portions = clean
            st.save(update_fields=["portions", "updated_at"])
            if st.status == "logged":
                services.unmark(request.user, meal, day)
                services.mark_eaten(request.user, meal, day)
        elif op == "swap":
            if not plan.allow_swaps:
                raise PermissionDenied("Your plan does not allow swaps. Tell your coach in your check-in.")
            item = get_object_or_404(MealItem, id=request.data.get("item"), option__meal=meal)
            st, _ = MealDayState.objects.get_or_create(client=request.user, date=day, meal=meal)
            alt_id = request.data.get("food")
            if alt_id in (None, "", str(item.food_id)):
                st.swaps.pop(str(item.id), None)
            else:
                alt = get_object_or_404(Food, id=alt_id)
                approved = item.food.swaps.filter(id=alt.id).exists()
                if not approved and not plan.allow_search_any:
                    raise PermissionDenied("Pick one of the approved swaps.")
                grams = same_kcal_grams(item.food, services._grams(item, st.portions.get(str(item.id))), alt)
                st.swaps[str(item.id)] = {"food": str(alt.id), "grams": grams}
                activity_log(f"swapped a food at {meal.name.lower()}", "meal", actor=request.user,
                             client=request.user, target_label=meal.name,
                             change=(item.food.name, f"{alt.name} {grams:g} g" if grams else alt.name))
            st.save(update_fields=["swaps", "updated_at"])
            if st.status == "logged":
                services.unmark(request.user, meal, day)
                services.mark_eaten(request.user, meal, day)
        elif op == "option":
            if not plan.allow_switch_options:
                raise PermissionDenied("Your plan does not allow switching options.")
            opt = get_object_or_404(meal.options, id=request.data.get("option"))
            st, _ = MealDayState.objects.get_or_create(client=request.user, date=day, meal=meal)
            st.option = opt
            st.portions, st.swaps = {}, {}
            st.save()
        else:
            raise serializers.ValidationError("Unknown action.")
        return Response(services.day_view(request.user, day, request))


def _log_meal(client, meal, day, verb):
    """Client profile → Activity: "Riya logged lunch · Paneer bowl, 480 kcal"."""
    rows = list(FoodLogEntry.objects.filter(client=client, date=day, meal=meal).values_list("name", "kcal"))
    note = ", ".join(n for n, _ in rows[:3]) + (f" +{len(rows) - 3}" if len(rows) > 3 else "")
    kcal = sum(k for _, k in rows)
    activity_log(verb, "meal", actor=client, client=client, target_label=meal.name,
                 meta={"note": ", ".join(x for x in (note, f"{kcal} kcal" if rows else "") if x)})


class MySwapOptionsView(APIView):
    """Swap sheet for one planned food: approved swaps with match % and matched grams."""

    permission_classes = [IsClient]

    def get(self, request, item_id):
        mp = services._active_plan(request.user, timezone.localdate())
        item = get_object_or_404(MealItem.objects.select_related("food", "unit"), id=item_id,
                                 option__meal__plan=mp.followed if mp else None)
        grams = services._grams(item)
        rows = [{**FoodPickSerializer(f).data, "match": match_percent(item.food, f),
                 "grams": same_kcal_grams(item.food, grams, f)} for f in item.food.swaps.all()]
        return Response({"planned": {**FoodPickSerializer(item.food).data, "grams": float(grams)},
                         "options": sorted(rows, key=lambda r: -r["match"]),
                         "can_search_any": mp.followed.allow_search_any})


class MyFoodLogViewSet(mixins.CreateModelMixin, mixins.DestroyModelMixin, viewsets.GenericViewSet):
    permission_classes = [IsClient]
    serializer_class = FoodLogSerializer

    def get_queryset(self):
        return FoodLogEntry.objects.filter(client=self.request.user)

    @extend_schema(request=LogFoodSerializer)
    def create(self, request):
        s = LogFoodSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        food = d.get("food")
        if food and food.owner_client_id and food.owner_client_id != request.user.id:
            raise PermissionDenied("That food is not yours.")
        name = d.pop("unit_name", "")
        if food and not d.get("unit") and name and name != "g":  # Undo of a deleted entry sends the unit by name
            d["unit"] = food.units.filter(name=name).first()
        day = sync_day(request.data.get("date"))
        e = services.log_food(request.user, day=day, **{k: v for k, v in d.items()})
        if request.data.get("logged_at"):
            e.logged_at = sync_time(request.data["logged_at"])
            e.save(update_fields=["logged_at"])
        activity_log(f"logged a food at {e.meal_name.lower()}" if e.meal_name else "logged a food", "meal",
                     actor=request.user, client=request.user, target_label=e.name,
                     meta={"note": f"{e.name}, {e.kcal} kcal" + (" · off plan" if e.source == "off_plan" else "")})
        return Response(FoodLogSerializer(e).data, status=201)

    def destroy(self, request, pk=None):
        e = get_object_or_404(self.get_queryset(), pk=pk)
        if e.date < timezone.localdate() - timedelta(days=1):
            raise serializers.ValidationError("You can only change today's log.")
        data = FoodLogSerializer(e).data
        e.delete()
        return Response(data)

    @action(detail=False, methods=["post"], url_path="copy-yesterday")
    def copy_yesterday(self, request):
        new, meals = services.copy_yesterday(request.user)
        return Response({"copied": len(new), "ids": [str(e.id) for e in new], "meals": meals})

    @action(detail=False, methods=["post"], url_path="undo-copy")
    def undo_copy(self, request):
        """Undo on the "Copied N foods from yesterday" toast."""
        ids = [i for i in (request.data.get("ids") or []) if isinstance(i, str)][:500]
        meals = [m for m in (request.data.get("meals") or []) if isinstance(m, int)][:50]
        return Response({"removed": services.undo_copy(request.user, ids, meals)})

    @action(detail=False, methods=["post"])
    def water(self, request):
        try:
            ml = int(request.data.get("ml", 250))
        except (TypeError, ValueError):
            raise serializers.ValidationError({"ml": ["Send a number of ml."]})
        if abs(ml) > 2000:
            raise serializers.ValidationError({"ml": ["Up to 2 L at a time."]})
        w = services.add_water(request.user, ml, day=sync_day(request.data.get("date")))
        return Response({"ml": w.ml})


class MyFoodSearchViewSet(mixins.ListModelMixin, mixins.CreateModelMixin, viewsets.GenericViewSet):
    """Log food: search team foods + 'My foods'; create a custom food (saved to My foods)."""

    permission_classes = [IsClient]
    search_fields = ["name", "brand"]

    def get_serializer_class(self):
        return FoodSerializer if self.action == "create" else FoodPickSerializer

    def get_queryset(self):
        qs = Food.objects.filter(Q(owner_client__isnull=True) | Q(owner_client=self.request.user)) \
            .prefetch_related("units").select_related("default_unit")
        g = self.request.query_params.get("group")
        if g == "mine":
            qs = qs.filter(owner_client=self.request.user)
        elif g in FOOD_GROUPS:
            qs = qs.filter(group=g)
        return qs.order_by("-owner_client", "source", "name")

    @action(detail=False)
    def recent(self, request):
        ids = []
        for fid in (FoodLogEntry.objects.filter(client=request.user, food__isnull=False)
                    .order_by("-logged_at").values_list("food_id", flat=True)[:100]):
            if fid not in ids:
                ids.append(fid)
            if len(ids) == 10:
                break
        foods = {f.id: f for f in self.get_queryset().filter(id__in=ids)}
        return Response(FoodPickSerializer([foods[i] for i in ids if i in foods], many=True).data)

    def create(self, request, *args, **kwargs):
        if "serving" not in request.data:
            return super().create(request, *args, **kwargs)
        # "Create custom food" on Log food: name, a serving ("1 katori") and its calories and macros.
        s = CustomFoodSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        grams = max(Decimal(100), d["protein"] + d["carbs"] + d["fat"])  # one serving, sized so per-100 g stays valid
        f = Decimal(100) / grams
        food = Food.objects.create(name=d["name"], group="other", diet=Diet.VEG, source=Food.Source.CLIENT,
                                   owner_client=request.user, created_by=request.user, kcal=d["kcal"] * f,
                                   protein=d["protein"] * f, carbs=d["carbs"] * f, fat=d["fat"] * f,
                                   default_quantity=1)
        unit = FoodUnit.objects.create(food=food, name=d["serving"], grams=grams)
        food.default_unit = unit
        food.save(update_fields=["default_unit"])
        return Response(FoodPickSerializer(food).data, status=201)

    def perform_create(self, serializer):
        serializer.save(source=Food.Source.CLIENT, owner_client=self.request.user, created_by=self.request.user)
