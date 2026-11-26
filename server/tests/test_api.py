from concurrent.futures import ThreadPoolExecutor
from uuid import uuid4
import json


def cart_order(client, customer, variant, **extra):
    assert client.patch(f'/v1/cart/{variant}', headers=customer, json={'quantity': 1}).status_code == 200
    fields = {'token': uuid4().hex, 'recipient': 'Анна Петрова', 'address': 'Учебная улица, дом 10', 'points': 0, **extra}
    response = client.post('/v1/orders', headers=customer, json=fields)
    assert response.status_code == 201, response.text
    return response.json(), fields


def test_catalog_search_and_exact_prices(client, product):
    data = client.get('/v1/catalog', params={'q': 'City', 'brand': 'PARA', 'model': 'CW-02'})
    assert data.status_code == 200
    assert data.json()['products'][0]['id'] == product['id']
    assert data.json()['products'][0]['price'] == '4990.00'
    assert client.get('/v1/catalog', params={'q': "'; DROP TABLE products; --"}).json()['products'] == []


def test_guest_cart_survives_new_requests_and_merges_once(client, product):
    guest = client.post('/v1/session').json()
    header = {'Authorization': 'Bearer ' + guest['token']}
    variant = product['variants'][0]['id']
    assert client.patch(f'/v1/cart/{variant}', json={'quantity': 2}, headers=header).json()['items'][0]['quantity'] == 2
    assert client.get('/v1/cart', headers=header).json()['subtotal'] == '9980.00'
    check = client.post('/v1/auth/phone', headers=header, json={'phone': '+79119999991'}).json()
    fields = {'challenge': check['challenge'], 'code': check['demo_code']}
    user = client.post('/v1/auth/verify', headers=header, json=fields).json()
    customer = {'Authorization': 'Bearer ' + user['token']}
    assert client.get('/v1/cart', headers=customer).json()['items'][0]['quantity'] == 2
    assert client.get('/v1/cart', headers=header).status_code == 401
    assert client.post('/v1/auth/verify', headers=customer, json=fields).status_code == 401


def test_size_price_is_rechecked_during_checkout(client, product, staff, customer):
    variant = product['variants'][1]['id']
    assert client.patch(f'/v1/staff/variants/{variant}/price', headers=staff, json={'price': '5290.00'}).status_code == 200
    assert client.patch(f'/v1/cart/{variant}', headers=customer, json={'quantity': 1}).json()['subtotal'] == '5290.00'
    assert client.patch(f'/v1/staff/variants/{variant}/price', headers=staff, json={'price': '5390.00'}).status_code == 200
    fields = {'token': uuid4().hex, 'recipient': 'Анна Петрова', 'address': 'Учебная улица, дом 10', 'points': 0}
    order = client.post('/v1/orders', headers=customer, json=fields).json()
    assert order['total'] == '5390.00'
    assert client.patch(f'/v1/staff/variants/{variant}/price', headers=staff, json={'price': None}).status_code == 200
    assert client.get(f"/v1/orders/{order['id']}", headers=customer).json()['total'] == '5390.00'


def test_checkout_idempotency_under_concurrent_requests(client, product, customer):
    variant = product['variants'][2]['id']
    assert client.patch(f'/v1/cart/{variant}', headers=customer, json={'quantity': 1}).status_code == 200
    before = client.get(f"/v1/products/{product['id']}").json()['variants'][2]['stock']
    fields = {'token': uuid4().hex, 'recipient': 'Анна Петрова', 'address': 'Учебная улица, дом 10', 'points': 0}
    with ThreadPoolExecutor(max_workers=2) as pool:
        values = list(pool.map(lambda _: client.post('/v1/orders', headers=customer, json=fields), range(2)))
    assert all(v.status_code == 201 for v in values)
    assert values[0].json()['id'] == values[1].json()['id']
    after = client.get(f"/v1/products/{product['id']}").json()['variants'][2]['stock']
    assert before - after == 1


def test_customer_cannot_cancel_accepted_order(client, product, staff, customer):
    order, _ = cart_order(client, customer, product['variants'][3]['id'])
    assert client.post(f"/v1/staff/orders/{order['id']}/status", json={'target': 'accepted'}, headers=staff).status_code == 200
    assert client.post(f"/v1/orders/{order['id']}/cancel", headers=customer).status_code == 400
    assert client.get(f"/v1/orders/{order['id']}", headers=customer).json()['status'] == 'accepted'


def test_rejection_returns_reserved_stock(client, product, staff, customer):
    variant = product['variants'][4]['id']
    before = client.get(f"/v1/products/{product['id']}").json()['variants'][4]['stock']
    order, _ = cart_order(client, customer, variant)
    assert client.post(f"/v1/staff/orders/{order['id']}/status", headers=staff, json={'target': 'rejected'}).status_code == 200
    after = client.get(f"/v1/products/{product['id']}").json()['variants'][4]['stock']
    assert before == after


def test_points_are_earned_once_after_completion(client, product, staff, customer):
    order, _ = cart_order(client, customer, product['variants'][5]['id'])
    assert client.get('/v1/profile', headers=customer).json()['points_balance'] == 0
    assert client.post(f"/v1/staff/orders/{order['id']}/status", headers=staff, json={'target': 'completed'}).status_code == 400
    assert client.post(f"/v1/staff/orders/{order['id']}/status", headers=staff, json={'target': 'accepted'}).status_code == 200
    for _ in range(2):
        assert client.post(f"/v1/staff/orders/{order['id']}/status", headers=staff, json={'target': 'completed'}).status_code == 200
    assert client.get('/v1/profile', headers=customer).json()['points_balance'] == 249


def test_foreign_order_and_staff_routes_are_protected(client, product, customer):
    order, _ = cart_order(client, customer, product['variants'][6]['id'])
    guest = client.post('/v1/session').json()
    header = {'Authorization': 'Bearer ' + guest['token']}
    assert client.get(f"/v1/orders/{order['id']}", headers=header).status_code == 403
    assert client.get('/v1/staff/products', headers=customer).status_code == 403
    assert client.get('/v1/staff/orders', headers=header).status_code == 403


def test_quantity_and_points_are_validated(client, product, customer):
    variant = product['variants'][7]['id']
    assert client.patch(f'/v1/cart/{variant}', headers=customer, json={'quantity': 99}).status_code == 400
    assert client.patch(f'/v1/cart/{variant}', headers=customer, json={'quantity': True}).status_code == 422
    assert client.patch(f'/v1/cart/{variant}', headers=customer, json={'quantity': 1}).status_code == 200
    fields = {'token': uuid4().hex, 'recipient': 'Анна Петрова', 'address': 'Учебная улица, дом 10', 'points': 1}
    assert client.post('/v1/orders', headers=customer, json=fields).status_code == 400


def test_logout_revokes_token(client, customer):
    assert client.delete('/v1/session', headers=customer).status_code == 200
    assert client.get('/v1/profile', headers=customer).status_code == 401


def test_staff_requires_password_and_code(client):
    response = client.post('/v1/auth/staff', json={'login': 'admin', 'password': 'wrong'})
    assert response.status_code == 401


def test_private_responses_are_not_cached(client, product, customer):
    assert client.get('/v1/cart', headers=customer).headers['cache-control'] == 'no-store'
    assert client.get('/v1/profile', headers=customer).headers['cache-control'] == 'no-store'
    assert client.get('/v1/catalog').headers['cache-control'] == 'public, max-age=15'


def test_invalid_photo_is_rejected(client, staff):
    fields = {'name': 'Тестовая модель', 'name_en': 'Test shoe', 'brand': 'PARA', 'model': 'INVALID-PHOTO',
              'description': 'Описание модели', 'description_en': 'Model description', 'price': '4990', 'is_active': True}
    response = client.post('/v1/staff/products', headers=staff, data={'payload': json.dumps(fields)}, files={'photo': ('shoe.png', b'not an image', 'image/png')})
    assert response.status_code == 400


def test_english_access_error_has_translation(client):
    response = client.get('/v1/profile', headers={'Accept-Language': 'en'})
    assert response.status_code == 401
    assert response.json()['message'] == 'Your session has expired. Sign in again.'
