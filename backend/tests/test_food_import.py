import io

from django.core.files.uploadedfile import SimpleUploadedFile
from openpyxl import Workbook, load_workbook

from apps.nutrition.models import Food

HEAD = ["Category", "Food", "Portion/Quantity", "Portion_g", "Protein_g", "Carbs_g", "Fat_g", "Calories_kcal",
        "Fiber_g", "Sodium_mg", "Iron_mg", "Calcium_mg", "Potassium_mg", "Source", "Main_Category"]


def _xlsx(rows):
    wb = Workbook()
    for r in rows:
        wb.active.append(r)
    buf = io.BytesIO()
    wb.save(buf)
    return SimpleUploadedFile("foods.xlsx", buf.getvalue())


def test_template_has_every_column_of_vimals_sheet(admin):
    r = admin.get("/api/v1/foods/import/template/")
    assert r.status_code == 200
    ws = load_workbook(io.BytesIO(r.content)).active
    assert [c.value for c in ws[1]] == HEAD
    assert ws.max_row >= 3


def test_vimals_sheet_imports_minerals_group_diet_and_source(admin):
    f = _xlsx([HEAD,
               ["Legumes", "Test moong dal (cooked)", "1 cup (150 g)", 150, 9, 23, 3.5, 180, 7, 350, 2, 40, 350,
                "IFCT", "Vegetarian"],
               ["Chicken", "Test chicken tikka", "100 g", 100, 31, 0, 3.6, 165, 0, 74, 1, 15, 256, "USDA",
                "Non-Vegetarian"],
               ["Snacks", "Test khakhra", "1 piece (20 g)", 20, 2, 14, 2, 80, 1, 100, 1, 10, 50, "Pack label",
                "Vegetarian"]])
    r = admin.post("/api/v1/foods/import/check/", {"file": f}, format="multipart")
    assert r.status_code == 200, r.content
    body = r.json()
    assert body["summary"]["new"] == 3 and body["summary"]["errors"] == 0
    r = admin.post(f"/api/v1/foods/import/{body['id']}/run/", {"duplicates": "skip"}, format="json")
    assert r.status_code == 200, r.content
    dal = Food.objects.get(name="Test moong dal (cooked)")
    assert (dal.group, dal.category, dal.diet, dal.source_note) == ("other", "Legumes", "veg", "IFCT")
    assert float(dal.sodium_mg) == 233.33 and float(dal.potassium_mg) == 233.33 and float(dal.fibre) == 4.67
    assert dal.default_unit.name == "1 cup" and float(dal.default_unit.grams) == 150
    tikka = Food.objects.get(name="Test chicken tikka")
    assert (tikka.group, tikka.category, tikka.diet, tikka.source_note) == ("other", "Chicken", "nonveg", "USDA")
    assert tikka.default_unit is None and float(tikka.default_quantity) == 100  # "100 g": 100 g serving
    kh = Food.objects.get(name="Test khakhra")
    assert (kh.group, kh.category) == ("other", "Snacks")


def test_category_name_only_kept_for_other(admin):
    f = Food.objects.create(name="Test bar", kcal=400, group="other", category="Snacks")
    r = admin.patch(f"/api/v1/foods/{f.id}/", {"group": "carbs"}, format="json")
    assert r.status_code == 200, r.content
    f.refresh_from_db()
    assert (f.group, f.category) == ("carbs", "")


def test_headers_with_brackets_still_match(admin):
    f = _xlsx([["Food", "Portion (g)", "Calories (kcal)", "Sodium (mg)"], ["Test plain curd", 100, 60, 46]])
    r = admin.post("/api/v1/foods/import/check/", {"file": f}, format="multipart")
    assert r.status_code == 200, r.content
    assert r.json()["rows"][0]["per100"]["sodium_mg"] == 46


# Vimal's sheet (22 Oct screenshot), first rows as typed there.
VIMAL = [
    ["Grains", "Rice, Basmati (raw)", "100 g", 100, 7.8, 80.67, 2.5, 367.5, 2.86, 5.1, 1.05, 21, 92.8, "IFCT/USDA", "Vegetarian"],
    ["Egg", "Egg (whole, raw)", "1 egg (50g)", 50, 6.3, 0.36, 5.3, 72, 0, 71, 0.88, 28, 63, "IFCT/USDA", "Non-Vegetarian"],
    ["Grains", "Oats (raw)", "100 g", 100, 13.15, 67.7, 6.5, 379, 10.1, 6, 4.25, 54, 362, "IFCT/USDA", "Vegetarian"],
    ["Grains", "Rice, White (raw)", "100 g", 100, 7, 80.4, 0.6, 361, 1.3, 5, 0.8, 10, 95, "IFCT/USDA", "Vegetarian"],
    ["Grains", "Roti (cooked, medium size (7\"))", "1 medium (40 g)", 40, 3, 18.5, 2, 110, 2, 5, 0.6, 10, 50, "IFCT", "Vegetarian"],
    ["Grains", "Multigrain Roti (Cooked size 7\")", "1 roti (40 g)", 40, 3.5, 18, 1.5, 110, 3, 6, 1, 15, 90, "IFCT/Estimated", "Vegetarian"],
    ["Cereals", "Muesli", "30 g", 30, 3, 20, 3.5, 120, 2.5, 45, 1, 20, 100, "USDA", "Vegetarian"],
    ["Chicken", "Chicken Breast (raw)", "100 g", 100, 31, 0, 3.6, 165, 0, 74, 1, 15, 256, "USDA", "Non-Vegetarian"],
    ["Legumes", "Soya Chunks (raw)", "100 g", 100, 52, 33, 0.5, 345, 13, 10, 20, 350, 1100, "IFCT", "Vegetarian"],
    ["Fruits", "Banana (medium)", "1 medium (118 g)", 118, 1.3, 27, 0.3, 105, 3, 1, 0.3, 6, 422, "USDA", "Vegetarian"],
    ["Fruits", "Apple (medium)", "1 (150 g)", 150, 0.3, 20, 0.2, 80, 3, 1, 0.1, 10, 195, "USDA", "Vegetarian"],
    ["Fruits", "Papaya (raw)", "100 g", 100, 0.5, 11, 0.3, 43, 1.8, 8, 0.3, 20, 182, "IFCT", "Vegetarian"],
    ["Fruits", "Seasonal Mix Fruits", "150 g", 150, 1, 25, 0.5, 110, 3, 5, 0.5, 20, 250, "Estimated", "Vegetarian"],
    ["Fats", "Ghee", "1 tsp (5 g)", 5, 0, 0, 5, 45, 0, 0, 0, 0, 1, "IFCT", "Vegetarian"],
    ["Beverages", "Tea with Milk & Sugar", "1 cup (150 ml)", 150, 2, 10, 3, 75, 0, 30, 0.2, 80, 100, "IFCT", "Vegetarian"],
    ["Legumes", "Dal (cooked)", "1 cup (150 g)", 150, 9, 23, 3.5, 180, 7, 350, 2, 40, 350, "IFCT", "Vegetarian"],
]


def test_vimals_full_sheet_imports_cleanly(admin):
    r = admin.post("/api/v1/foods/import/check/", {"file": _xlsx([HEAD, *VIMAL])}, format="multipart")
    assert r.status_code == 200, r.content
    body = r.json()
    assert body["summary"]["errors"] == 0, [x for x in body["rows"] if x["errors"]]
    r = admin.post(f"/api/v1/foods/import/{body['id']}/run/", {"duplicates": "update"}, format="json")
    assert r.status_code == 200, r.content
    rice = Food.objects.get(name="Rice, Basmati (raw)")
    assert (rice.group, rice.category, rice.diet, rice.source_note, float(rice.kcal)) == ("other", "Grains", "veg", "IFCT/USDA", 367.5)
    assert rice.default_unit is None and float(rice.default_quantity) == 100
    egg = Food.objects.get(name="Egg (whole, raw)")
    assert egg.diet == "egg" and (egg.default_unit.name, float(egg.default_unit.grams)) == ("1 egg", 50)
    assert Food.objects.get(name="Chicken Breast (raw)").diet == "nonveg"
    assert (Food.objects.get(name="Ghee").group, Food.objects.get(name="Ghee").category) == ("fats", "")
    tea = Food.objects.get(name="Tea with Milk & Sugar")
    assert (tea.group, tea.category) == ("beverages", "") and (tea.default_unit.name, float(tea.default_unit.grams)) == ("1 cup", 150)
    muesli = Food.objects.get(name="Muesli")
    assert (muesli.group, muesli.category) == ("other", "Cereals") and float(muesli.default_quantity) == 30
    apple = Food.objects.get(name="Apple (medium)")
    assert (apple.default_unit.name, float(apple.default_unit.grams)) == ("1 piece", 150)
