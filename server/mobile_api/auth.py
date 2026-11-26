"""Сеансы устройства и учебный вход с SMS-подтверждением."""
from datetime import datetime, timedelta, timezone
import hashlib
import hmac
import os
import re
import secrets
from fastapi import HTTPException
from .database import connect, row
from . import guest_cart


def hashed(value):
    """Получение SHA-256 без хранения исходного токена в базе."""
    return hashlib.sha256(value.encode()).hexdigest()


def code_hash(token, code):
    """Вычисление HMAC для кода конкретной проверки."""
    return hmac.new(os.environ['SECRET_KEY'].encode(), (token + code).encode(), hashlib.sha256).hexdigest()


def phone_number(value):
    """Приведение российского номера к единой записи."""
    digits = re.sub(r'[^0-9]', '', value)
    if len(digits) == 10:
        digits = '7' + digits
    if len(digits) == 11 and digits.startswith('8'):
        digits = '7' + digits[1:]
    if not re.fullmatch(r'7[0-9]{10}', digits):
        raise ValueError('Укажите телефон в формате +7XXXXXXXXXX.')
    return '+' + digits


def session(header, required=None):
    """Проверка токена и роли перед доступом к данным."""
    token = header[7:] if header and header.startswith('Bearer ') else ''
    if not re.fullmatch(r'[A-Za-z0-9_-]{43}', token):
        raise HTTPException(401, 'Сеанс завершён. Войдите снова.')
    value = row('SELECT * FROM mobile_sessions WHERE token_hash=%s AND expires_at>CURRENT_TIMESTAMP', (hashed(token),))
    if not value:
        raise HTTPException(401, 'Сеанс завершён. Войдите снова.')
    if required and value['role'] != required:
        raise HTTPException(403, 'Для действия нужна другая учётная запись.')
    return value


def issue(connection, role, user_id=None, guest_id=None):
    """Создание случайного токена для ограниченного по времени сеанса."""
    token = secrets.token_urlsafe(32)
    hours = 8 if role != 'customer' else 24 * 7
    connection.execute('''INSERT INTO mobile_sessions(token_hash,role,user_id,guest_cart_id,expires_at)
        VALUES (%s,%s,%s,%s,%s)''',
        (hashed(token), role, user_id, guest_id, datetime.now(timezone.utc) + timedelta(hours=hours)))
    return {'token': token, 'role': role}


def create_guest():
    """Создание гостевой корзины и связанного с ней сеанса устройства."""
    identifier = secrets.token_urlsafe(32)
    with connect() as connection:
        connection.execute('DELETE FROM mobile_auth_challenges WHERE expires_at<=CURRENT_TIMESTAMP')
        connection.execute('DELETE FROM mobile_sessions WHERE expires_at<=CURRENT_TIMESTAMP')
        connection.execute('DELETE FROM guest_carts WHERE expires_at<=CURRENT_TIMESTAMP')
        connection.execute('INSERT INTO guest_carts(id) VALUES (%s)', (identifier,))
        return issue(connection, 'guest', guest_id=identifier)


def begin(role, phone='', login='', password='', current=None):
    """Создание учебной проверки телефона после необходимых проверок."""
    if os.getenv('DEMO_AUTH', 'false').lower() != 'true':
        raise HTTPException(503, 'Доставка SMS ещё не подключена.')
    identity = phone_number(phone) if role == 'customer' else 'staff'
    token = secrets.token_urlsafe(32)
    code = os.getenv('CUSTOMER_DEMO_CODE', '123456') if role == 'customer' else os.environ['ADMIN_SMS_DEMO_CODE']
    error = None
    with connect() as connection:
        connection.execute('INSERT INTO mobile_auth_limits(identity_hash) VALUES (%s) ON CONFLICT DO NOTHING', (hashed(identity),))
        limit = connection.execute('SELECT *,blocked_until>CURRENT_TIMESTAMP AS blocked FROM mobile_auth_limits WHERE identity_hash=%s FOR UPDATE', (hashed(identity),)).fetchone()
        if limit['blocked']:
            error = HTTPException(429, 'Слишком много попыток. Повторите вход через пять минут.')
        elif role == 'staff' and not (
            secrets.compare_digest(login.encode(), os.environ['ADMIN_LOGIN'].encode())
            and secrets.compare_digest(password.encode(), os.environ['ADMIN_PASSWORD'].encode())
            ):
            fail(connection, hashed(identity))
            error = HTTPException(401, 'Логин или пароль неверен.')
        else:
            phone = identity if role == 'customer' else os.environ['ADMIN_PHONE']
            connection.execute('''INSERT INTO mobile_auth_challenges
        (token_hash,role,phone,session_hash,code_hash,expires_at)
            VALUES (%s,%s,%s,%s,%s,CURRENT_TIMESTAMP+INTERVAL '5 minutes')''',
            (hashed(token), role, phone, current['token_hash'] if current else None, code_hash(token, code)))
    if error:
        raise error
    return {'challenge': token, 'phone': phone[2:] + ' ••• ••• ' + phone[-4:], 'demo_code': code, 'demo': True}


def fail(connection, identity):
    """Увеличение счётчика ошибок и включение временной блокировки."""
    connection.execute('''UPDATE mobile_auth_limits SET
        failures=CASE WHEN blocked_until<CURRENT_TIMESTAMP THEN 1 ELSE failures+1 END,
        blocked_until=CASE WHEN blocked_until<CURRENT_TIMESTAMP THEN NULL
            WHEN failures>=4 THEN CURRENT_TIMESTAMP+INTERVAL '5 minutes' ELSE blocked_until END
        WHERE identity_hash=%s''', (identity,))


def verify(token, entered, current=None):
    """Однократная проверка кода и объединение гостевой корзины."""
    error = None
    result = None
    with connect() as connection:
        challenge = connection.execute('''SELECT * FROM mobile_auth_challenges
            WHERE token_hash=%s AND expires_at>CURRENT_TIMESTAMP FOR UPDATE''', (hashed(token),)).fetchone()
        if not challenge or challenge['attempts'] >= 5:
            error = HTTPException(401, 'Проверка завершена. Запросите новый код.')
        elif challenge['session_hash'] and (not current or current['token_hash'] != challenge['session_hash']):
            error = HTTPException(401, 'Проверка относится к другому сеансу.')
        elif not secrets.compare_digest(challenge['code_hash'], code_hash(token, entered)):
            connection.execute('UPDATE mobile_auth_challenges SET attempts=attempts+1 WHERE token_hash=%s', (hashed(token),))
            fail(connection, hashed(challenge['phone'] if challenge['role'] == 'customer' else 'staff'))
            error = HTTPException(401, 'Неверный код подтверждения.')
        elif challenge['role'] == 'staff':
            result = issue(connection, 'staff')
        else:
            user = connection.execute('''INSERT INTO users(phone) VALUES (%s)
                ON CONFLICT(phone) DO UPDATE SET phone=EXCLUDED.phone RETURNING id''', (challenge['phone'],)).fetchone()
            result = issue(connection, 'customer', user_id=user['id'])
            if current and current['role'] == 'guest':
                result['cart_adjusted'] = guest_cart.merge({'guest_cart_id': current['guest_cart_id']}, user['id'], connection)
                connection.execute('DELETE FROM mobile_sessions WHERE token_hash=%s', (current['token_hash'],))
            if result:
                connection.execute('DELETE FROM mobile_auth_challenges WHERE token_hash=%s', (hashed(token),))
        if error:
            raise error
    return result
