from apps.nutrition.swaps import name_label


def test_a_logged_amount_reads_as_a_portion_not_quantity_and_unit_name():
    assert name_label(2, "1 piece") == "2 pieces"
    assert name_label(1, "1 piece") == "1 piece"
    assert name_label(150, "g") == "150 g"
    assert name_label(1, "serving") == "serving"
