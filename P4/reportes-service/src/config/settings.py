import os

from dotenv import load_dotenv

load_dotenv()


class Settings:
    PORT: int = int(os.getenv("PORT", "8000"))

    DB_HOST: str = os.getenv("DB_HOST", "postgres-reportes")
    DB_PORT: int = int(os.getenv("DB_PORT", "5432"))
    DB_USER: str = os.getenv("DB_USER", "postgres")
    DB_PASSWORD: str = os.getenv("DB_PASSWORD", "postgres")
    DB_NAME: str = os.getenv("DB_NAME", "reportes_db")

    JWT_SECRET: str = os.getenv("JWT_SECRET", "changeme")

    AUTHZ_SERVICE_URL: str = os.getenv("AUTHZ_SERVICE_URL", "http://authz-service:4000")
    AUTHZ_MAX_RETRIES: int = int(os.getenv("AUTHZ_MAX_RETRIES", "3"))
    AUTHZ_RETRY_BACKOFF_MS: int = int(os.getenv("AUTHZ_RETRY_BACKOFF_MS", "300"))

    PRODUCTOS_SERVICE_URL: str = os.getenv("PRODUCTOS_SERVICE_URL", "http://productos-service:8000")


settings = Settings()
