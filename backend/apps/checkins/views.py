import json
from datetime import timedelta

from django.db import transaction
from django.db.models import Count, Q
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import mixins, serializers, status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.activity.services import log as activity_log
from apps.clients.services import get_visible_client, visible_clients
from apps.common.mixins import SoftDeleteViewMixin
from apps.common.pagination import TimelineCursorPagination
from apps.common.permissions import IsClient, IsStaff

from . import services
from .defaults import TEMPLATES
from .models import Form, FormRequest, Measurement, PhotoSet, ProgressPhoto, Question, Submission, WeightLog
from .serializers import (
    FormCreateSerializer,
    FormDetailSerializer,
    FormRequestSerializer,
    FormRowSerializer,
    MeasurementSerializer,
    PhotoSetSerializer,
    ProgressPhotoSerializer,
    QuestionsSerializer,
    ReviewSerializer,
    SubmissionDetailSerializer,
    SubmissionRowSerializer,
    WeightLogSerializer,
)


def _client_or_404(user, pk):
    try:
        return get_visible_client(user, pk)
    except Exception:
        from django.http import Http404

        raise Http404


def _senders():
    """Form id → names of automations that send it ('Client onboarding · on approval')."""
    from apps.automations.models import Automation, Step

    out = {}
    for s in Step.objects.filter(kind="form", automation__deleted_at__isnull=True).select_related("automation"):
        fid = s.config.get("form")
        if fid:
            a = s.automation
            out.setdefault(fid, []).append(f"{a.name} · {a.get_trigger_display().lower()}" if a.trigger else a.name)
    return {k: v for k, v in out.items()}


# ---------------------------------------------------------------- forms (staff)
class FormViewSet(SoftDeleteViewMixin, viewsets.ModelViewSet):
    permission_classes = [IsStaff]
    search_fields = ["name"]
    ordering = ["-updated_at"]
    http_method_names = ["get", "post", "patch", "put", "delete"]

    def check_permissions(self, request):
        super().check_permissions(request)
        u = request.user
        if u.is_trainer and request.method not in ("GET", "HEAD", "OPTIONS"):
            if not u.trainer_profile.has_perm("checkins.edit_forms"):
                raise PermissionDenied("Your access does not include editing forms. Ask Vimal for more access.")

    def get_queryset(self):
        qs = Form.objects.annotate(n_questions=Count("questions", filter=Q(questions__is_removed=False)))
        p = self.request.query_params
        if self.action == "list":
            qs = qs.filter(status="archived") if p.get("tab") == "archived" else qs.exclude(status="archived")
            if p.get("type"):
                qs = qs.filter(type=p["type"])
        if self.action in ("retrieve", "questions"):
            qs = qs.prefetch_related("questions")
        return qs

    def get_serializer_class(self):
        return FormDetailSerializer if self.action in ("retrieve", "questions") else FormRowSerializer

    def get_serializer_context(self):
        ctx = super().get_serializer_context()
        if self.action == "list":
            import uuid

            ctx["senders"] = {uuid.UUID(str(k)): v for k, v in _senders().items()}
        return ctx

    @action(detail=False)
    def counts(self, request):
        qs = Form.objects.exclude(status="archived")
        by = dict(qs.values_list("type").annotate(n=Count("id")))
        return Response({"all": qs.count(), "archived": Form.objects.filter(status="archived").count(), **by})

    def create(self, request, *args, **kwargs):
        s = FormCreateSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        with transaction.atomic():
            f = Form.objects.create(name=" ".join(d["name"].split()), type=d["type"], created_by=request.user)
            if d["start"] == "template":
                Question.objects.bulk_create([Question(form=f, order=i, **q)
                                              for i, q in enumerate(TEMPLATES[d["type"]])])
        activity_log("created a form", "checkin", actor=request.user, target=f, target_label=f.name)
        return Response(FormDetailSerializer(Form.objects.prefetch_related("questions").get(id=f.id)).data,
                        status=201)

    @action(detail=True, methods=["get", "put"])
    def questions(self, request, pk=None):
        """The builder saves the whole question list (ids keep old answers linked)."""
        f = self.get_object()
        if request.method == "PUT":
            s = QuestionsSerializer(data=request.data)
            s.is_valid(raise_exception=True)
            with transaction.atomic():
                keep = []
                for i, qd in enumerate(s.validated_data["questions"]):
                    q = f.questions.filter(id=qd.get("id")).first() if qd.get("id") else None
                    q = q or Question(form=f)
                    for k, v in qd.items():
                        if k != "id":
                            setattr(q, k, v)
                    q.order = i
                    q.save()
                    keep.append(q.id)
                gone = f.questions.exclude(id__in=keep)
                # questions with answers are kept off the form (answers stay readable) instead of deleted
                from .models import Answer

                answered = set(Answer.objects.filter(question__in=gone).values_list("question_id", flat=True))
                gone.exclude(id__in=answered).delete()
                Question.objects.filter(id__in=answered).update(is_removed=True, order=999)
                f.save(update_fields=["updated_at"])
            f = self.get_queryset().get(id=f.id)
        return Response(FormDetailSerializer(f).data)

    @action(detail=True, methods=["post"])
    def publish(self, request, pk=None):
        f = self.get_object()
        if not f.questions.filter(is_removed=False).exists():
            raise serializers.ValidationError("Add at least one question first.")
        f.status = Form.Status.PUBLISHED
        f.save(update_fields=["status", "updated_at"])
        return Response(FormRowSerializer(f).data)

    @action(detail=True, methods=["post"])
    def duplicate(self, request, pk=None):
        src = self.get_object()
        with transaction.atomic():
            f = Form.objects.create(name=f"{src.name} (copy)"[:120], type=src.type, created_by=request.user)
            Question.objects.bulk_create([
                Question(form=f, order=q.order, text=q.text, type=q.type, options=q.options,
                         scale_labels=q.scale_labels, allow_other=q.allow_other, help_text=q.help_text,
                         required=q.required, metric=q.metric) for q in src.questions.filter(is_removed=False)])
        return Response(FormRowSerializer(f).data, status=201)

    @action(detail=True, methods=["post"])
    def archive(self, request, pk=None):
        f = self.get_object()
        prev = f.status
        f.status = Form.Status.ARCHIVED
        f.save(update_fields=["status", "updated_at"])
        return Response({**FormRowSerializer(f).data, "previous_status": prev})

    @action(detail=True, methods=["post"])
    def unarchive(self, request, pk=None):
        f = Form.objects.get(pk=pk)
        f.status = request.data.get("status") if request.data.get("status") in ("draft", "published") else "draft"
        f.save(update_fields=["status", "updated_at"])
        return Response(FormRowSerializer(f).data)

    @action(detail=True)
    def answers(self, request, pk=None):
        """'See Riya's answers': latest submissions of this form, scoped to visible clients."""
        f = self.get_object()
        qs = (Submission.objects.filter(form=f, client__in=visible_clients(request.user))
              .select_related("client", "form").order_by("-created_at")[:50])
        return Response(SubmissionRowSerializer(qs, many=True).data)


# ---------------------------------------------------------------- review queue (staff)
class CheckinReviewViewSet(mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    """Trainer → Check-ins, dashboard 'Check-ins to review', client profile → Logs → check-ins."""

    permission_classes = [IsStaff]
    pagination_class = TimelineCursorPagination

    def get_queryset(self):
        u = self.request.user
        qs = (Submission.objects.filter(client__in=visible_clients(u))
              .select_related("client", "form", "reviewed_by")
              .annotate(n_photos=Count("answers", filter=~Q(answers__photo="") & Q(answers__photo__isnull=False))))
        if u.is_trainer:
            tp = u.trainer_profile
            allowed = [t for t, key in (("daily", "checkins.daily"), ("weekly", "checkins.weekly"))
                       if tp.has_perm(key)] + ["survey", "onboarding", "waiver"]
            qs = qs.filter(form_type__in=allowed)
        p = self.request.query_params
        tab = p.get("tab", "to_review")
        if tab == "to_review":
            qs = qs.filter(reviewed_at__isnull=True, form_type__in=["weekly", "daily", "survey"])
        elif tab == "reviewed":
            qs = qs.filter(reviewed_at__isnull=False)
        kind = p.get("kind")
        if kind in ("weekly", "daily"):
            qs = qs.filter(form_type=kind)
        elif kind == "monthly":
            qs = qs.filter(form_type="survey")
        if p.get("client"):
            qs = qs.filter(client_id=p["client"])
        if self.action == "retrieve":
            qs = qs.prefetch_related("answers__question")
        return qs

    def get_serializer_class(self):
        return SubmissionDetailSerializer if self.action == "retrieve" else SubmissionRowSerializer

    @action(detail=False)
    def counts(self, request):
        base = Submission.objects.filter(client__in=visible_clients(request.user),
                                         form_type__in=["weekly", "daily", "survey"])
        waiting = base.filter(reviewed_at__isnull=True)
        return Response({
            "to_review": waiting.count(),
            "over_48h": waiting.filter(created_at__lt=timezone.now() - timedelta(hours=48)).count(),
            "reviewed": base.filter(reviewed_at__isnull=False).count(),
            "all": base.count(),
        })

    def retrieve(self, request, *args, **kwargs):
        sub = self.get_object()
        data = SubmissionDetailSerializer(sub, context={"request": request}).data
        prev = (Submission.objects.filter(client=sub.client, form_type=sub.form_type, created_at__lt=sub.created_at)
                .prefetch_related("answers__question").order_by("-created_at").first())
        data["previous"] = SubmissionDetailSerializer(prev, context={"request": request}).data if prev else None
        cp = sub.client.client_profile
        from apps.clients.metrics import active_program

        pa = active_program(sub.client, sub.date)
        data["plan"] = {"name": pa.effective_program.name, "week": services.week_number(sub.client, sub.date)} \
            if pa else None
        data["trainer"] = cp.trainer.full_name if cp.trainer else None
        return Response(data)

    @action(detail=True, methods=["post"])
    def review(self, request, pk=None):
        sub = self.get_object()
        s = ReviewSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        services.review(sub, actor=request.user, reply=s.validated_data.get("reply", ""))
        return Response(SubmissionRowSerializer(sub).data)

    @action(detail=True, methods=["post"])
    def unreview(self, request, pk=None):
        sub = services.unreview(self.get_object())
        return Response(SubmissionRowSerializer(sub).data)


class ClientFormsView(APIView):
    """Client profile → Forms tab: sent forms (Filled / Waiting) + Send a form."""

    permission_classes = [IsStaff]

    def get(self, request, client_pk):
        client = _client_or_404(request.user, client_pk)
        rows = FormRequest.objects.filter(client=client).select_related("form").order_by("-created_at")
        sendable = Form.objects.filter(status="published").annotate(n=Count("questions", filter=Q(questions__is_removed=False)))
        return Response({
            "sent": FormRequestSerializer(rows, many=True).data,
            "can_send": [{"id": str(f.id), "name": f.name, "type": f.type, "questions": f.n} for f in sendable],
        })

    def post(self, request, client_pk):
        client = _client_or_404(request.user, client_pk)
        form = get_object_or_404(Form, id=request.data.get("form"), status="published")
        req = services.send_form(client, form, actor=request.user)
        return Response(FormRequestSerializer(req).data, status=201)


class ClientProgressView(APIView):
    """Client profile → Progress tab (staff): weights, measurements, photo sets."""

    permission_classes = [IsStaff]

    def get(self, request, client_pk):
        client = _client_or_404(request.user, client_pk)
        if request.user.is_trainer and not request.user.trainer_profile.has_perm("checkins.photos"):
            photos = []
        else:
            photos = PhotoSetSerializer(PhotoSet.objects.filter(client=client).prefetch_related("photos"),
                                        many=True, context={"request": request}).data
        return Response({
            "weights": WeightLogSerializer(WeightLog.objects.filter(client=client).order_by("date"), many=True).data,
            "measurements": MeasurementSerializer(Measurement.objects.filter(client=client).order_by("date"),
                                                  many=True).data,
            "photo_sets": photos,
        })


# ---------------------------------------------------------------- client app
def _data_url_file(item, name):
    import base64
    import binascii

    from django.core.files.base import ContentFile

    head, _, body = str(item).partition(",")
    ext = {"image/png": "png", "image/webp": "webp"}.get(head[5:].split(";")[0], "jpg")
    if not head.startswith("data:image/") or not body:
        raise serializers.ValidationError({"photos": ["Send each photo as an image."]})
    try:
        raw = base64.b64decode(body, validate=True)
    except (binascii.Error, ValueError):
        raise serializers.ValidationError({"photos": ["Send each photo as an image."]})
    return ContentFile(raw, name=f"{name}.{ext}")


class MyCheckinsView(APIView):
    """Check-ins page: the daily and weekly cards, the numbers on top, and past check-ins (weekly or daily,
    missed ones included), paged with `before=YYYY-MM-DD`."""

    permission_classes = [IsClient]

    def get(self, request):
        from django.utils.dateparse import parse_date

        from .client_page import checkins_page

        tab = request.query_params.get("tab", "weekly")
        if tab not in ("weekly", "daily"):
            raise serializers.ValidationError({"tab": ["Use weekly or daily."]})
        before = parse_date(request.query_params.get("before") or "") if request.query_params.get("before") else None
        data = checkins_page(request.user, tab, before)
        data["pending_forms"] = FormRequestSerializer(
            FormRequest.objects.filter(client=request.user, filled_at__isnull=True).select_related("form"),
            many=True).data
        return Response(data)


class MySubmissionViewSet(mixins.RetrieveModelMixin, mixins.CreateModelMixin, mixins.DestroyModelMixin,
                          viewsets.GenericViewSet):
    """Send a check-in or a requested form; Edit answers; View what you sent."""

    permission_classes = [IsClient]
    parser_classes = [MultiPartParser, FormParser, JSONParser]
    serializer_class = SubmissionDetailSerializer

    def get_queryset(self):
        return Submission.objects.filter(client=self.request.user).prefetch_related("answers__question")

    @staticmethod
    def _payload(request):
        answers = request.data.get("answers") or {}
        if isinstance(answers, str):
            try:
                answers = json.loads(answers)
            except ValueError:
                raise serializers.ValidationError({"answers": ["Send answers as JSON."]})
        files = {}
        for key in request.FILES:
            if key.startswith("photo_"):
                files[key[6:]] = request.FILES.getlist(key)
        # The app's offline outbox sends photos as data URLs: {"<question id>": ["data:image/jpeg;base64,…"]}.
        photos = request.data.get("photos") or {}
        if isinstance(photos, dict):
            for qid, items in photos.items():
                if isinstance(items, dict):  # {"front": …, "side": …, "back": …}
                    items = [(pose, items.get(pose)) for pose in ("front", "side", "back") if items.get(pose)]
                else:
                    items = list(zip(("front", "side", "back"), items or []))
                for pose, item in items:
                    f = _data_url_file(item, pose)
                    f.pose = pose
                    files.setdefault(str(qid), []).append(f)
        return answers, files

    def create(self, request):
        u = request.user
        req = None
        if request.data.get("request"):
            req = get_object_or_404(FormRequest, id=request.data["request"], client=u)
            form = req.form
        else:
            form = get_object_or_404(Form, id=request.data.get("form"), status="published",
                                     type__in=["weekly", "daily"])
        if form.type == "daily" and Submission.objects.filter(
                client=u, form_type="daily", date=request.data.get("date") or timezone.localdate()).exists():
            raise serializers.ValidationError("You sent today's check-in. Use Edit answers to change it.")
        answers, files = self._payload(request)
        from apps.common.utils import sync_day

        day = sync_day(request.data.get("date"), back_days=2)
        sub = services.submit(u, form, answers, files, request_obj=req, note=request.data.get("note", "") or "",
                              day=day)
        if request.data.get("logged_at"):  # sent from the outbox later: keep the time it was filled in
            from apps.common.utils import sync_time

            Submission.objects.filter(id=sub.id).update(created_at=sync_time(request.data["logged_at"]))
        data = SubmissionDetailSerializer(self.get_queryset().get(id=sub.id), context={"request": request}).data
        data["streak"] = services.streak(u, "daily") if form.type == "daily" else None
        return Response(data, status=201)

    def partial_update(self, request, pk=None):
        sub = get_object_or_404(self.get_queryset(), pk=pk)
        if sub.date < timezone.localdate() - timedelta(days=6):
            raise serializers.ValidationError("This check-in is too old to change.")
        answers, files = self._payload(request)
        note = request.data.get("note", (sub.metrics or {}).get("note", "")) or ""
        services.submit(request.user, sub.form, answers, files, submission=sub, note=note)
        return Response(SubmissionDetailSerializer(self.get_queryset().get(id=sub.id),
                                                   context={"request": request}).data)


    def destroy(self, request, pk=None):
        """Undo on the "check-in sent" toast: only a check-in your coach has not opened yet, sent today."""
        sub = get_object_or_404(self.get_queryset(), pk=pk)
        if sub.reviewed_at or sub.created_at < timezone.now() - timedelta(hours=24):
            raise serializers.ValidationError("Your coach already has this check-in. Use Edit answers instead.")
        PhotoSet.objects.filter(submission=sub).delete()
        sub.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class MyProgressView(APIView):
    """Progress tab: weight series + range, measurements, photo timeline, lifts, adherence by week."""

    permission_classes = [IsClient]

    def get(self, request):
        from apps.clients.metrics import adherence

        u = request.user
        rng = request.query_params.get("range", "12wk")
        days = {"4wk": 28, "12wk": 84, "6mo": 182}.get(rng)
        weights = WeightLog.objects.filter(client=u).order_by("date")
        if days:
            weights = weights.filter(date__gte=timezone.localdate() - timedelta(days=days))
        cp = u.client_profile
        weeks = []
        end = timezone.localdate() - timedelta(days=1)
        for i in range(6):
            e = end - timedelta(days=7 * i)
            weeks.append({"week_ending": e, "adherence": adherence(u, 7, e)})
        return Response({
            "weights": WeightLogSerializer(weights, many=True).data,
            "current": float(cp.current_weight_kg) if cp.current_weight_kg else None,
            "goal": float(cp.target_weight_kg) if cp.target_weight_kg else None,
            "start": float(cp.start_weight_kg) if cp.start_weight_kg else None,
            "measurements": MeasurementSerializer(Measurement.objects.filter(client=u).order_by("date"),
                                                  many=True).data,
            "photo_sets": PhotoSetSerializer(PhotoSet.objects.filter(client=u).prefetch_related("photos"),
                                             many=True, context={"request": request}).data,
            "adherence_weeks": list(reversed(weeks)),
            "lifts": _lifts(u),
        })


def _lifts(user, limit=4):
    from django.db.models import Max

    from apps.training.models import SetLog

    top = (SetLog.objects.filter(workout__client=user, done=True, is_warmup=False, weight_kg__isnull=False)
           .values("exercise_id", "exercise__name").annotate(n=Count("id"), best=Max("weight_kg"))
           .order_by("-n")[:limit])
    out = []
    for row in top:
        series = (SetLog.objects.filter(workout__client=user, exercise_id=row["exercise_id"], done=True,
                                        is_warmup=False, weight_kg__isnull=False)
                  .values("workout__date").annotate(w=Max("weight_kg")).order_by("workout__date"))
        best = (SetLog.objects.filter(workout__client=user, exercise_id=row["exercise_id"], done=True,
                                      weight_kg=row["best"]).order_by("-reps").first())
        out.append({"exercise": row["exercise_id"], "name": row["exercise__name"],
                    "best": {"weight_kg": float(row["best"]), "reps": best.reps if best else None},
                    "series": [{"date": s["workout__date"], "kg": float(s["w"])} for s in series]})
    return out


class MyWeightViewSet(mixins.ListModelMixin, mixins.CreateModelMixin, mixins.DestroyModelMixin,
                      viewsets.GenericViewSet):
    permission_classes = [IsClient]
    serializer_class = WeightLogSerializer
    pagination_class = None

    def get_queryset(self):
        return WeightLog.objects.filter(client=self.request.user)

    def create(self, request):
        s = WeightLogSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        if s.validated_data["date"] > timezone.localdate():
            raise serializers.ValidationError({"date": ["Pick today or an earlier day."]})
        w, _ = WeightLog.objects.update_or_create(client=request.user, date=s.validated_data["date"],
                                                  defaults={"weight_kg": s.validated_data["weight_kg"]})
        latest = self.get_queryset().order_by("-date").first()
        cp = request.user.client_profile
        cp.current_weight_kg = latest.weight_kg
        cp.save(update_fields=["current_weight_kg"])
        return Response(WeightLogSerializer(w).data, status=201)


class MyMeasurementViewSet(MyWeightViewSet):
    serializer_class = MeasurementSerializer

    def get_queryset(self):
        return Measurement.objects.filter(client=self.request.user)

    def create(self, request):
        s = MeasurementSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = dict(s.validated_data)
        day = d.pop("date")
        m, _ = Measurement.objects.update_or_create(client=request.user, date=day, defaults=d)
        return Response(MeasurementSerializer(m).data, status=201)


class MyPhotoView(APIView):
    """Add photos sheet: one pose into today's set."""

    permission_classes = [IsClient]
    parser_classes = [MultiPartParser, FormParser]

    def post(self, request):
        s = ProgressPhotoSerializer(data=request.data)
        if not request.FILES.get("image"):
            raise serializers.ValidationError({"image": ["Take or choose a photo first — Then save it to today's "
                                                         "set"]})
        s.is_valid(raise_exception=True)
        p = services.save_photo(request.user, pose=s.validated_data["pose"], image=s.validated_data["image"])
        return Response(ProgressPhotoSerializer(p, context={"request": request}).data, status=201)

    def delete(self, request):
        pid = request.query_params.get("id")
        get_object_or_404(ProgressPhoto, id=pid, photo_set__client=request.user).delete()
        return Response(status=status.HTTP_204_NO_CONTENT)
