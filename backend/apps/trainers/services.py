from apps.accounts.models import Role

from .models import AccessMode, TrainerProfile


def ensure_admin_trainer_profile(user):
    """Admin ka trainer profile hamesha hota hai (is_owner=True), taaki woh khud ko trainer ke roop me
    invite link, clients aur profile screens me use kar sake. Pehle se hai to kuch nahi badalta."""
    if user.role != Role.ADMIN:
        return None
    profile, _ = TrainerProfile.objects.get_or_create(
        user=user,
        defaults={"is_owner": True, "access_mode": AccessMode.ALL, "max_clients": 40,
                  "speciality": [], "languages": ["Hindi", "English"]},
    )
    return profile
