from pathlib import Path
import itertools
import json
import os
import pytest
from fastapi.testclient import TestClient
from mobile_api.main import app
from mobile_api.database import connect

counter = itertools.count(1000)


@pytest.fixture(scope='session')
def client():
    assert 'para_mobile_test_' in os.environ['DATABASE_URL']
    with TestClient(app) as value:
        yield value


@pytest.fixture(scope='session')
def staff(client):
    check = client.post('/v1/auth/staff', json={'login': os.environ['ADMIN_LOGIN'], 'password': os.environ['ADMIN_PASSWORD']}).json()
    value = client.post('/v1/auth/verify', json={'challenge': check['challenge'], 'code': check['demo_code']}).json()
    return {'Authorization': 'Bearer ' + value['token']}


@pytest.fixture(scope='session')
def product(client, staff):
    fields = {'name': 'Кеды City White', 'name_en': 'City White trainers', 'brand': 'PARA', 'model': 'CW-02',
              'description': 'Светлые кеды для повседневных прогулок.', 'description_en': 'Light trainers for everyday walks.',
              'price': '4990.00', 'is_active': True}
    value = client.post('/v1/staff/products', data={'payload': json.dumps(fields)},
                        files={'photo': ('photo-city.png', (Path(__file__).resolve().parents[2]/'images/photo-city.png').read_bytes(), 'image/png')}, headers=staff)
    assert value.status_code == 200, value.text
    product = value.json()
    for variant in product['variants']:
        assert client.post(f"/v1/staff/variants/{variant['id']}/stock", json={'quantity': 50}, headers=staff).status_code == 200
    return product


@pytest.fixture
def customer(client):
    guest = client.post('/v1/session').json()
    header = {'Authorization': 'Bearer ' + guest['token']}
    phone = '+7911' + str(next(counter)).zfill(7)
    check = client.post('/v1/auth/phone', headers=header, json={'phone': phone}).json()
    result = client.post('/v1/auth/verify', headers=header, json={'challenge': check['challenge'], 'code': check['demo_code']})
    assert result.status_code == 200, result.text
    return {'Authorization': 'Bearer ' + result.json()['token']}
