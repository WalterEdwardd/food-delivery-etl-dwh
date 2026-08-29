from src.config.source_schema import SOURCE_SCHEMA


EXPECTED_ENTITIES = {
    "customer",
    "delivery_partner",
    "delivery_performance",
    "menu_item",
    "order",
    "order_item",
    "rating",
    "restaurant",
}


EXPECTED_COLUMN_COUNTS = {
    "customer": 4,
    "delivery_partner": 7,
    "delivery_performance": 7,
    "menu_item": 6,
    "order": 11,
    "order_item": 8,
    "rating": 8,
    "restaurant": 7,
}


def test_expected_entities_exist():
    assert set(SOURCE_SCHEMA.keys()) == EXPECTED_ENTITIES


def test_expected_column_counts():
    for entity, expected_count in EXPECTED_COLUMN_COUNTS.items():
        actual_count = len(SOURCE_SCHEMA[entity]["columns"])

        assert actual_count == expected_count


def test_each_entity_has_file_pattern():
    for entity, config in SOURCE_SCHEMA.items():
        assert "file_pattern" in config
        assert config["file_pattern"]


def test_each_column_has_required_metadata():
    for entity, config in SOURCE_SCHEMA.items():
        for column, metadata in config["columns"].items():
            assert "source_type" in metadata
            assert "required" in metadata
            assert "business_key" in metadata


def test_delivery_id_is_candidate_business_key():
    metadata = SOURCE_SCHEMA["delivery_performance"]["columns"]["delivery_id"]

    assert metadata["candidate_business_key"] is True
    assert metadata["business_key"] is False