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
