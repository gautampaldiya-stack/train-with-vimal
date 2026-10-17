from celery import shared_task


@shared_task
def send_scheduled_forms():
    """Client profile → Send a form: later / on a repeat, and the one reminder 24 h after a form went out."""
    from .client_forms import run_schedules

    return run_schedules()
