from decimal import Decimal

from django.utils import timezone

from apps.accounts.models import User
from apps.checkins.models import Form, Measurement, Question, WeightLog
from apps.checkins.services import submit


def test_tagged_answers_of_any_form_go_to_weight_height_and_measurements(db):
    """D-88: a question's Progress tag (metric) saves its answer to weigh-ins, the profile or measurements."""
    riya = User.objects.get(email="riya@example.com")
    form = Form.objects.create(name="Monthly body check", type="survey", status="published")
    w = Question.objects.create(form=form, order=1, text="Current weight", type="number", metric="weight")
    h = Question.objects.create(form=form, order=2, text="Height", type="number", metric="height")
    m = Question.objects.create(form=form, order=3, text="Muscle mass from InBody", type="number", metric="muscle_mass")
    n = Question.objects.create(form=form, order=4, text="Anything else?", type="short")
    submit(riya, form, {str(w.id): "66.4", str(h.id): "163", str(m.id): "27.5", str(n.id): "no"})
    today = timezone.localdate()
    assert WeightLog.objects.get(client=riya, date=today).weight_kg == Decimal("66.4")
    riya.client_profile.refresh_from_db()
    assert riya.client_profile.height_cm == Decimal("163.0")
    assert Measurement.objects.filter(client=riya).order_by("-date").first().values["muscle_mass"] == 27.5


def test_a_checkin_can_be_edited_only_on_the_day_it_was_sent(client_user):
    from datetime import timedelta

    from apps.checkins.models import Submission

    riya = User.objects.get(email="riya@example.com")
    form = Form.objects.filter(type="weekly", status="published").first()
    old = Submission.objects.create(form=form, form_type="weekly", client=riya,
                                    date=timezone.localdate() - timedelta(days=1))
    r = client_user.patch(f"/api/v1/me/submissions/{old.id}/", {"answers": {}}, format="json")
    assert r.status_code == 400 and "only on the day" in r.json()["error"]["message"]


def test_builder_question_settings_measures_suggestions_and_photo_skip():
    """Probid 2026-10-31: the coach builds every weekly question: a measures card with the measurements it asks,
    the note's suggestion chips, and whether a photo question offers "No photos this week"."""
    from apps.checkins.serializers import QuestionSerializer

    s = QuestionSerializer(data={"text": "Body measurements", "type": "measures", "options": ["waist", "hips"]})
    assert s.is_valid(), s.errors
    assert s.validated_data["options"] == ["waist", "hips"]
    assert not QuestionSerializer(data={"text": "M", "type": "measures", "options": ["elbow"]}).is_valid()
    s = QuestionSerializer(data={"text": "Notes", "type": "long", "suggestions": [" Nothing  this week ", ""]})
    assert s.is_valid() and s.validated_data["suggestions"] == ["Nothing this week"]
    s = QuestionSerializer(data={"text": "Weight", "type": "number", "suggestions": ["x"]})
    assert s.is_valid() and s.validated_data["suggestions"] == []
    s = QuestionSerializer(data={"text": "Photos", "type": "photo", "allow_skip": False})
    assert s.is_valid() and s.validated_data["allow_skip"] is False
