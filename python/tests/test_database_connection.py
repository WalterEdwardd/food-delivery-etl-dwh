from src.config.database import get_connection


def test_database_connection():
    connection = get_connection()

    cursor = connection.cursor()
    cursor.execute("SELECT DB_NAME()")

    database_name = cursor.fetchone()[0]

    connection.close()

    assert database_name == "FoodDeliveryDW"