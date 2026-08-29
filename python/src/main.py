from config import settings
from utils.logger import get_logger


logger = get_logger(__name__)


def main():
    logger.info("Food Delivery ETL pipeline initialized.")
    logger.info("Database: %s", settings.DB_DATABASE)
    logger.info("Server: %s", settings.DB_SERVER)


if __name__ == "__main__":
    main()