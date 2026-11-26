"""Запуск учебных сценариев в отдельной базе без изменения данных магазина."""
from pathlib import Path
from uuid import uuid4
from decimal import Decimal
import json
import os
import argparse
import psycopg
from psycopg import sql
from psycopg.conninfo import make_conninfo
from dotenv import dotenv_values

ROOT = Path(__file__).resolve().parent


def prepare_database(settings):
    """Создание изолированной базы для проверки экранов на устройстве."""
    name = 'para_mobile_demo_' + uuid4().hex[:8]
    with psycopg.connect(make_conninfo(settings['DATABASE_URL'], dbname='postgres'), autocommit=True) as connection:
        connection.execute(sql.SQL('CREATE DATABASE {}').format(sql.Identifier(name)))
    database = make_conninfo(settings['DATABASE_URL'], dbname=name)
    with psycopg.connect(database) as connection:
        for file in ('store.sql', 'mobile.sql'):
            connection.execute((ROOT / 'database' / file).read_text(encoding='utf-8'))
    return name, database


def prepare_examples(client):
    """Добавление учебных товаров через API и начисление первых баллов."""
    challenge = client.post('/v1/auth/staff', json={'login': os.environ['ADMIN_LOGIN'], 'password': os.environ['ADMIN_PASSWORD']}).json()
    result = client.post('/v1/auth/verify', json={'challenge': challenge['challenge'], 'code': challenge['demo_code']})
    result.raise_for_status()
    staff = {'Authorization': 'Bearer ' + result.json()['token']}
    examples = [
        ('Кеды City White', 'City White trainers', 'CW-02', '4990.00', 'photo-city.png'),
        ('Кроссовки Trail Black', 'Trail Black trainers', 'TB-01', '7490.00', 'trail-black.webp'),
        ('Кроссовки Classic Runner', 'Classic Runner trainers', 'CR-03', '6490.00', 'classic-runner.webp'),
    ]
    products = []
    for name, english, model, price, photo in examples:
        fields = {'name': name, 'name_en': english, 'brand': 'PARA', 'model': model,
                'description': 'Удобная обувь для прогулок и движения каждый день.',
                'description_en': 'Comfortable shoes for everyday walks and movement.',
                'price': price, 'is_active': True}
        result = client.post('/v1/staff/products', data={'payload': json.dumps(fields)},
                            files={'photo': (photo, (ROOT.parent / 'images' / photo).read_bytes(), 'image/webp' if photo.endswith('.webp') else 'image/png')}, headers=staff)
        result.raise_for_status()
        product = result.json()
        for variant in product['variants']:
            result = client.post(f"/v1/staff/variants/{variant['id']}/stock", json={'quantity': 30}, headers=staff)
            result.raise_for_status()
            if variant['size'] == 42:
                result = client.patch(f"/v1/staff/variants/{variant['id']}/price", json={'price': str(Decimal(price) + 300)}, headers=staff)
                result.raise_for_status()
        products.append(product)
    guest = client.post('/v1/session').json()
    headers = {'Authorization': 'Bearer ' + guest['token']}
    phone = '+79119990001'
    challenge = client.post('/v1/auth/phone', json={'phone': phone}, headers=headers).json()
    result = client.post('/v1/auth/verify', json={'challenge': challenge['challenge'], 'code': challenge['demo_code']}, headers=headers)
    result.raise_for_status()
    customer = {'Authorization': 'Bearer ' + result.json()['token']}
    client.patch('/v1/cart/' + str(products[0]['variants'][4]['id']), json={'quantity': 1}, headers=customer).raise_for_status()
    result = client.post('/v1/orders', json={'token': uuid4().hex, 'recipient': 'Учебный покупатель',
                                                'address': 'Учебный адрес', 'points': 0}, headers=customer)
    result.raise_for_status()
    order = result.json()['id']
    for target in ('accepted', 'completed'):
        client.post(f'/v1/staff/orders/{order}/status', json={'target': target}, headers=staff).raise_for_status()
    return {'phone': phone, 'products': [value['id'] for value in products]}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8015)
    arguments = parser.parse_args()
    settings = dotenv_values(ROOT / '.env')
    name, database = prepare_database(settings)
    os.environ.update({**settings, 'DATABASE_URL': database, 'MEDIA_ROOT': str(ROOT / 'media')})
    from fastapi.testclient import TestClient
    from mobile_api.main import app
    import uvicorn
    with TestClient(app) as client:
        examples = prepare_examples(client)
        (ROOT / '.demo.json').write_text(json.dumps({'database': name, **examples}), encoding='utf-8')
        print('Изолированный учебный API подготовлен. База ' + name, flush=True)
        uvicorn.run(app, host='127.0.0.1', port=arguments.port)
