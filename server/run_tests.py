"""Запуск API-проверок в новой изолированной базе PostgreSQL."""
from pathlib import Path
from uuid import uuid4
import os
import subprocess
import sys
import psycopg
from psycopg import sql
from psycopg.conninfo import make_conninfo
from dotenv import dotenv_values

ROOT = Path(__file__).resolve().parent

if __name__ == '__main__':
    settings = dotenv_values(ROOT / '.env')
    name = 'para_mobile_test_' + uuid4().hex[:8]
    source = settings['DATABASE_URL']
    with psycopg.connect(make_conninfo(source, dbname='postgres'), autocommit=True) as connection:
        connection.execute(sql.SQL('CREATE DATABASE {}').format(sql.Identifier(name)))
    database = make_conninfo(source, dbname=name)
    with psycopg.connect(database) as connection:
        for file in ('store.sql', 'mobile.sql'):
            connection.execute((ROOT / 'database' / file).read_text(encoding='utf-8'))
    environment = {**os.environ, **settings, 'DATABASE_URL': database, 'MEDIA_ROOT': str(ROOT / 'media')}
    print('Тестовая база создана. Данные магазина не используются.', flush=True)
    result = subprocess.run([sys.executable, '-m', 'pytest', 'tests', '-v'], cwd=ROOT, env=environment)
    print('Тестовая база сохранена под именем ' + name, flush=True)
    raise SystemExit(result.returncode)
