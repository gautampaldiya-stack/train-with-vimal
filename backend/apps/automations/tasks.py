from celery import shared_task
from django.db import transaction

from . import engine
from .models import AutomationRun


@shared_task
def advance_run(run_id):
    with transaction.atomic():
        run = (AutomationRun.objects.select_for_update(skip_locked=True).select_related("automation", "client")
               .filter(id=run_id).first())
        if run is not None:
            engine.advance(run)


@shared_task
def process_due_runs():
    return engine.process_due_runs()


@shared_task
def poll_triggers():
    return engine.poll_triggers()
