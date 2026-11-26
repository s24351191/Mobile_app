"""Подключение к общей базе данных магазина."""
from pathlib import Path
import os
import psycopg
from psycopg.rows import dict_row
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]
load_dotenv(ROOT / '.env')
DATABASE_URL = os.getenv('DATABASE_URL', 'postgresql://postgres:123@localhost:5432/shoe_store')
MEDIA_ROOT = Path(os.getenv('MEDIA_ROOT', str(ROOT / 'media'))).resolve()


def connect():
    """Открытие соединения с автоматическим завершением транзакции."""
    return psycopg.connect(DATABASE_URL, row_factory=dict_row, connect_timeout=5)


def rows(query, values=()):
    """Чтение нескольких строк параметризованным запросом."""
    with connect() as connection:
        return connection.execute(query, values).fetchall()


def row(query, values=()):
    """Чтение одной строки или возврат None."""
    with connect() as connection:
        return connection.execute(query, values).fetchone()
