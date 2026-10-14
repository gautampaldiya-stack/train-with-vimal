# Rulebook — Backend

- New models extend `TimeStampedModel` or `SoftDeleteModel`. Add indexes for every filter a screen uses.
- Business logic lives in `services.py`; views stay thin.
- Use `select_related` / `prefetch_related` / annotations; no queries in loops on list endpoints.
- Push/email/realtime only through `apps.notifications` (`notify`, templates). Never send directly from a view.
- Long or scheduled work goes to Celery; add it to `CELERY_BEAT_SCHEDULE` if periodic.
- Tests in `backend/tests/`, run with `pytest`. Seeds: `seed_defaults` (library), `seed_demo` (demo data).
