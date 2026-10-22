from celery import shared_task


@shared_task
def email_domain_check():
    """Settings → Integrations → Email sending: look at the DNS records again while they are not all in place."""
    from .integrations import recheck_pending_domain

    recheck_pending_domain()
