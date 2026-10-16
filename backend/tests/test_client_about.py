from rest_framework.test import APIClient


def test_about_page_reads_gym_contact_and_coach(db):
    r = APIClient(HTTP_HOST="localhost").get("/api/v1/gym/")
    assert r.status_code == 200
    g = r.json()
    assert g["phone"] == "+91 70874 03476" and g["whatsapp"] == g["phone"]
    assert g["website"] == "trainwithvimal.com" and g["hours"] == "Mon–Sat, 9 am – 9 pm"
    assert g["coach"]["name"] == "Vimal" and g["coach"]["role"] == "Head coach · Online"
    assert [s["label"] for s in g["coach"]["stats"]] == ["Years coaching", "Transformations", "Followers"]


def test_admin_edits_the_about_words(admin):
    r = admin.patch("/api/v1/settings/gym/", {"tagline": "Coaching that fits your day", "support_hours": "Every day, 7 am – 10 pm",
                                              "coach_stats": [["12+", "Years coaching"]]}, format="json")
    assert r.status_code == 200, r.content
    g = APIClient(HTTP_HOST="localhost").get("/api/v1/gym/").json()
    assert g["tagline"] == "Coaching that fits your day" and g["hours"] == "Every day, 7 am – 10 pm"
    assert g["coach"]["stats"] == [{"value": "12+", "label": "Years coaching"}]


def test_more_uses_the_same_support_hours(client_user):
    assert client_user.get("/api/v1/me/account/").json()["gym"]["hours"] == "Mon–Sat, 9 am – 9 pm"
