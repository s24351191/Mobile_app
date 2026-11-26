"""JSON API для покупателей и сотрудников магазина обуви."""
from contextlib import asynccontextmanager
from decimal import Decimal
from pathlib import Path
import json
import os
import logging
import psycopg
from fastapi import FastAPI, Form, Header, HTTPException, Request, UploadFile
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from starlette.concurrency import run_in_threadpool
from PIL import UnidentifiedImageError
from .database import MEDIA_ROOT, connect, row, rows
from .messages import language
from .errors import human
from . import auth, catalog, guest_cart, models, store


@asynccontextmanager
async def lifespan(application):
    """Проверка настроек до приёма запросов приложения."""
    if len(os.getenv('SECRET_KEY', '')) < 32:
        raise RuntimeError('В .env требуется SECRET_KEY длиной не менее 32 символов.')
    MEDIA_ROOT.mkdir(parents=True, exist_ok=True)
    yield


app = FastAPI(title='PARA Mobile API', version='1.0.0', lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origin_regex=r'http://(localhost|127\.0\.0\.1):[0-9]+',
                   allow_methods=['GET', 'POST', 'PATCH', 'DELETE'], allow_headers=['Authorization', 'Content-Type', 'Accept-Language'])
app.mount('/static', StaticFiles(directory=MEDIA_ROOT, check_dir=False), name='static')


def result(data, status=200):
    """Преобразование денежных значений Decimal в точные строки JSON."""
    return JSONResponse(jsonable_encoder(data, custom_encoder={Decimal: lambda v: format(v, '.2f')}), status_code=status)


@app.middleware('http')
async def request_context(request, call_next):
    """Выбор языка и запрет хранения ответов с личными данными."""
    code = 'en' if request.headers.get('accept-language', '').lower().startswith('en') else 'ru'
    marker = language.set(code)
    try:
        response = await call_next(request)
        if request.url.path == '/v1/catalog' and response.status_code == 200:
            response.headers['Cache-Control'] = 'public, max-age=15'
        elif request.url.path.startswith('/static/uploads/'):
            response.headers['Cache-Control'] = 'public, max-age=31536000, immutable'
        else:
            response.headers['Cache-Control'] = 'no-store'
        response.headers['Content-Language'] = code
        return response
    finally:
        language.reset(marker)


@app.exception_handler(ValueError)
async def invalid_value(request, error):
    return result({'message': human(str(error))}, 400)


@app.exception_handler(HTTPException)
async def http_error(request, error):
    return result({'message': human(error.detail)}, error.status_code)


@app.exception_handler(RequestValidationError)
async def invalid_fields(request, error):
    return result({'message': 'Проверьте заполнение полей.' if language.get() == 'ru' else 'Check the entered values.'}, 422)


@app.exception_handler(psycopg.errors.UniqueViolation)
async def duplicate(request, error):
    return result({'message': 'Такая модель уже существует.' if language.get() == 'ru' else 'This model already exists.'}, 409)


@app.exception_handler(psycopg.Error)
async def database_failure(request, error):
    logging.getLogger('para.mobile').error('Database request failed', exc_info=True)
    return result({'message': 'База данных временно недоступна.' if language.get() == 'ru' else 'The database is temporarily unavailable.'}, 503)


@app.get('/v1/health')
def health():
    row('SELECT 1 AS healthy')
    return {'status': 'ok'}


@app.post('/v1/session', status_code=201)
def new_session():
    return result(auth.create_guest(), 201)


@app.get('/v1/catalog')
def products(q: str = '', brand: str = '', model: str = ''):
    return result(catalog.search(q, brand, model))


@app.get('/v1/products/{identifier}')
def detail(identifier: int):
    item = catalog.product(identifier)
    if not item:
        raise HTTPException(404, 'Товар не найден.')
    return result(item)


@app.post('/v1/auth/phone')
def phone_login(fields: models.PhoneLogin, authorization: str | None = Header(default=None)):
    current = auth.session(authorization)
    return result(auth.begin('customer', phone=fields.phone, current=current))


@app.post('/v1/auth/staff')
def staff_login(fields: models.StaffLogin):
    return result(auth.begin('staff', login=fields.login, password=fields.password))


@app.post('/v1/auth/verify')
def verify_login(fields: models.Verification, authorization: str | None = Header(default=None)):
    current = auth.session(authorization) if authorization else None
    return result(auth.verify(fields.challenge, fields.code, current))


@app.delete('/v1/session')
def logout(authorization: str | None = Header(default=None)):
    current = auth.session(authorization)
    with connect() as connection:
        connection.execute('DELETE FROM mobile_sessions WHERE token_hash=%s', (current['token_hash'],))
    return {'ok': True}


@app.get('/v1/profile')
def profile(authorization: str | None = Header(default=None)):
    current = auth.session(authorization)
    if current['role'] != 'customer':
        return {'role': current['role'], 'points_balance': 0}
    value = row('SELECT phone,points_balance FROM users WHERE id=%s', (current['user_id'],))
    return {'role': 'customer', **value}


@app.get('/v1/cart')
def get_cart(authorization: str | None = Header(default=None)):
    current = auth.session(authorization)
    if current['role'] == 'staff':
        raise HTTPException(403, 'Для покупки войдите как покупатель.')
    value = store.cart(current['user_id']) if current['role'] == 'customer' else guest_cart.cart({'guest_cart_id': current['guest_cart_id']})
    return result(value)


@app.patch('/v1/cart/{variant_id}')
def change_cart(variant_id: int, fields: models.CartChange, authorization: str | None = Header(default=None)):
    current = auth.session(authorization)
    if current['role'] == 'customer':
        store.change_cart(current['user_id'], variant_id, fields.quantity, fields.add)
    elif current['role'] == 'guest':
        guest_cart.change({'guest_cart_id': current['guest_cart_id']}, variant_id, fields.quantity, fields.add)
    else:
        raise HTTPException(403, 'Для покупки войдите как покупатель.')
    return get_cart(authorization)


@app.post('/v1/orders', status_code=201)
def checkout(fields: models.Checkout, authorization: str | None = Header(default=None)):
    current = auth.session(authorization, 'customer')
    identifier = store.checkout(current['user_id'], fields.token, fields.recipient.strip(), fields.address.strip(), fields.points)
    return result(order_data(identifier, current), 201)


def order_data(identifier, current):
    """Чтение заказа с обязательной проверкой владельца."""
    value = row('''SELECT o.*,u.phone FROM orders o JOIN users u ON u.id=o.user_id
        WHERE o.id=%s AND (%s OR o.user_id=%s)''', (identifier, current['role'] == 'staff', current['user_id']))
    if not value:
        raise HTTPException(404, 'Заказ не найден.')
    value['items'] = rows('SELECT *,unit_price*quantity AS line_total FROM order_items WHERE order_id=%s ORDER BY id', (identifier,))
    return value


@app.get('/v1/orders')
def orders(authorization: str | None = Header(default=None)):
    current = auth.session(authorization, 'customer')
    identifiers = rows('SELECT id FROM orders WHERE user_id=%s ORDER BY id DESC LIMIT 50', (current['user_id'],))
    return result([order_data(item['id'], current) for item in identifiers])


@app.get('/v1/orders/{identifier}')
def order_detail(identifier: int, authorization: str | None = Header(default=None)):
    current = auth.session(authorization)
    if current['role'] not in ('customer', 'staff'):
        raise HTTPException(403, 'Сначала войдите в учётную запись.')
    return result(order_data(identifier, current))


@app.post('/v1/orders/{identifier}/cancel')
def cancel_order(identifier: int, authorization: str | None = Header(default=None)):
    current = auth.session(authorization, 'customer')
    store.transition_order(identifier, 'cancelled', current['user_id'])
    return result(order_data(identifier, current))


@app.get('/v1/staff/products')
def staff_products(authorization: str | None = Header(default=None)):
    auth.session(authorization, 'staff')
    return result(catalog.search(staff=True))


@app.get('/v1/staff/products/{identifier}')
def staff_detail(identifier: int, authorization: str | None = Header(default=None)):
    auth.session(authorization, 'staff')
    value = catalog.product(identifier, True)
    if not value:
        raise HTTPException(404, 'Товар не найден.')
    return result(value)


@app.post('/v1/staff/products')
async def save_product(payload: str = Form(), photo: UploadFile | None = None,
                       authorization: str | None = Header(default=None)):
    """Приём полей карточки и необязательной фотографии multipart."""
    await run_in_threadpool(auth.session, authorization, 'staff')
    try:
        value = json.loads(payload)
        identifier = value.pop('id', None)
        fields = models.ProductFields.model_validate(value).model_dump()
        catalog.money(fields['price'])
    except (ValueError, TypeError):
        raise HTTPException(422, 'Проверьте поля карточки товара.')
    path = None
    if photo:
        try:
            data = await photo.read(5 * 1024 * 1024 + 1)
            path = await run_in_threadpool(catalog.upload_photo, data)
        except (UnidentifiedImageError, OSError):
            raise HTTPException(400, 'Не удалось прочитать фотографию.')
    try:
        identifier = await run_in_threadpool(catalog.save, identifier, fields, path)
    except Exception:
        if path:
            (MEDIA_ROOT / 'uploads' / Path(path).name).unlink(missing_ok=True)
        raise
    return result(await run_in_threadpool(catalog.product, identifier, True))


@app.post('/v1/staff/variants/{identifier}/stock')
def stock(identifier: int, fields: models.StockChange, authorization: str | None = Header(default=None)):
    auth.session(authorization, 'staff')
    with connect() as connection:
        value = connection.execute('UPDATE product_variants SET stock=stock+%s WHERE id=%s RETURNING product_id', (fields.quantity, identifier)).fetchone()
        if not value:
            raise HTTPException(404, 'Размер не найден.')
    return result(catalog.product(value['product_id'], True))


@app.patch('/v1/staff/variants/{identifier}/price')
def size_price(identifier: int, fields: models.SizePrice, authorization: str | None = Header(default=None)):
    auth.session(authorization, 'staff')
    price = catalog.money(fields.price) if fields.price else None
    with connect() as connection:
        value = connection.execute('UPDATE product_variants SET price=%s WHERE id=%s RETURNING product_id', (price, identifier)).fetchone()
        if not value:
            raise HTTPException(404, 'Размер не найден.')
    return result(catalog.product(value['product_id'], True))


@app.get('/v1/staff/orders')
def staff_orders(authorization: str | None = Header(default=None)):
    current = auth.session(authorization, 'staff')
    return result([order_data(item['id'], current) for item in rows('SELECT id FROM orders ORDER BY id DESC LIMIT 100')])


@app.post('/v1/staff/orders/{identifier}/status')
def order_action(identifier: int, fields: models.OrderAction, authorization: str | None = Header(default=None)):
    current = auth.session(authorization, 'staff')
    store.transition_order(identifier, fields.target)
    return result(order_data(identifier, current))
