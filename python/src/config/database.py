import pyodbc

def get_connection():
    connection_string = (
        "DRIVER={ODBC Driver 17 for SQL Server};"
        "SERVER=localhost\SQLEXPRESS;"
        "DATABASE=FoodDeliveryDW;"
        "TRUSTED_CONNECTION=yes;"
    )

    return pyodbc.connect(connection_string)
