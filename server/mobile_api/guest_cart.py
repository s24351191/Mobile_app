"""Гостевая корзина с серверным хранением и однократным объединением после входа."""
from decimal import Decimal
from contextlib import nullcontext
import re
import secrets

from .database import connect, row, rows
from .messages import t

SESSION_KEY = 'guest_cart_id'


def token(session):
    """Проверка случайного идентификатора гостевой корзины в серверном сеансе."""
    value = session.get(SESSION_KEY, '')
    return value if isinstance(value, str) and re.fullmatch(r'[A-Za-z0-9_-]{43}', value) else None


def prepare(session):
    """Создание пустой гостевой корзины для последующего сохранения позиций."""
    identifier = token(session)
    existing = row('''SELECT id FROM guest_carts WHERE id=%s
        AND expires_at>CURRENT_TIMESTAMP AND merged_user_id IS NULL''', (identifier,)) if identifier else None
    if existing:
        return
    identifier = secrets.token_urlsafe(32)
    with connect() as conn:
        conn.execute('DELETE FROM guest_carts WHERE expires_at<=CURRENT_TIMESTAMP')
        conn.execute('INSERT INTO guest_carts(id) VALUES (%s)', (identifier,))
    session[SESSION_KEY] = identifier


def count(session):
    """Подсчёт позиций доступной гостевой корзины без создания новых записей."""
    identifier = token(session)
    if not identifier:
        return 0
    return row('''SELECT COALESCE(SUM(i.quantity),0) AS n
        FROM guest_cart_items i JOIN guest_carts g ON g.id=i.cart_id
        WHERE g.id=%s AND g.expires_at>CURRENT_TIMESTAMP AND g.merged_user_id IS NULL''',
        (identifier,))['n']


def cart(session):
    """Чтение выбранных размеров и актуальных цен без доступа к чужой корзине."""
    identifier = token(session)
    items = [] if not identifier else rows('''SELECT i.variant_id,i.quantity,v.size,v.stock,
        p.id AS product_id,p.name,p.name_en,p.model,p.photo,p.is_active,
        COALESCE(v.price,p.price) AS price,
        COALESCE(v.price,p.price)*i.quantity AS line_total
        FROM guest_cart_items i JOIN guest_carts g ON g.id=i.cart_id
        JOIN product_variants v ON v.id=i.variant_id JOIN products p ON p.id=v.product_id
        WHERE g.id=%s AND g.expires_at>CURRENT_TIMESTAMP AND g.merged_user_id IS NULL
        ORDER BY i.variant_id''', (identifier,))
    return {'items': items,
        'subtotal': sum((item['line_total'] for item in items), Decimal('0.00')),
        'max_points': 0}


def change(session, variant_id, quantity, add=False):
    """Изменение гостевой корзины под блокировкой её строки в PostgreSQL."""
    if not 0 <= quantity <= 99:
        raise ValueError(t('errors.quantity_range'))
    identifier = token(session)
    with connect() as conn:
        conn.execute('DELETE FROM guest_carts WHERE expires_at<=CURRENT_TIMESTAMP')
        guest = conn.execute('''SELECT *,expires_at>CURRENT_TIMESTAMP AS available
            FROM guest_carts WHERE id=%s FOR UPDATE''', (identifier,)).fetchone() if identifier else None
        if not guest or guest['merged_user_id'] is not None:
            if quantity == 0:
                return
            identifier = secrets.token_urlsafe(32)
            conn.execute('INSERT INTO guest_carts(id) VALUES (%s)', (identifier,))
        old = conn.execute('SELECT quantity FROM guest_cart_items WHERE cart_id=%s AND variant_id=%s',
            (identifier, variant_id)).fetchone()
        quantity += old['quantity'] if old and add else 0
        if quantity == 0:
            conn.execute('DELETE FROM guest_cart_items WHERE cart_id=%s AND variant_id=%s',
                (identifier, variant_id))
        else:
            variant = conn.execute('''SELECT v.stock,p.is_active FROM product_variants v
                JOIN products p ON p.id=v.product_id WHERE v.id=%s''', (variant_id,)).fetchone()
            if not variant or not variant['is_active']:
                raise ValueError(t('errors.product_unavailable'))
            if quantity > 99 or quantity > variant['stock']:
                raise ValueError(t('errors.insufficient_stock'))
            conn.execute('''INSERT INTO guest_cart_items(cart_id,variant_id,quantity) VALUES (%s,%s,%s)
                ON CONFLICT(cart_id,variant_id) DO UPDATE SET quantity=EXCLUDED.quantity''',
                (identifier, variant_id, quantity))
        conn.execute("UPDATE guest_carts SET expires_at=CURRENT_TIMESTAMP+INTERVAL '8 hours' WHERE id=%s",
            (identifier,))
    session[SESSION_KEY] = identifier


def merge(session, user_id, connection=None):
    """Однократное объединение корзин с ограничением количества текущим остатком."""
    identifier = token(session)
    if not identifier:
        return False
    adjusted = False
    with (nullcontext(connection) if connection is not None else connect()) as conn:
        conn.execute('SELECT id FROM users WHERE id=%s FOR UPDATE', (user_id,))
        guest = conn.execute('''SELECT *,expires_at>CURRENT_TIMESTAMP AS available
            FROM guest_carts WHERE id=%s FOR UPDATE''', (identifier,)).fetchone()
        if guest and guest['available'] and guest['merged_user_id'] is None:
            items = conn.execute('''SELECT i.variant_id,i.quantity,v.stock,p.is_active
                FROM guest_cart_items i JOIN product_variants v ON v.id=i.variant_id
                JOIN products p ON p.id=v.product_id WHERE i.cart_id=%s ORDER BY i.variant_id''',
                (identifier,)).fetchall()
            for item in items:
                old = conn.execute('SELECT quantity FROM cart_items WHERE user_id=%s AND variant_id=%s',
                    (user_id, item['variant_id'])).fetchone()
                wanted = item['quantity'] + (old['quantity'] if old else 0)
                amount = min(wanted, item['stock'], 99) if item['is_active'] else 0
                adjusted |= amount != wanted
                if amount:
                    conn.execute('''INSERT INTO cart_items(user_id,variant_id,quantity) VALUES (%s,%s,%s)
                        ON CONFLICT(user_id,variant_id) DO UPDATE SET quantity=EXCLUDED.quantity''',
                        (user_id, item['variant_id'], amount))
                elif old:
                    conn.execute('DELETE FROM cart_items WHERE user_id=%s AND variant_id=%s',
                        (user_id, item['variant_id']))
            conn.execute('UPDATE guest_carts SET merged_user_id=%s WHERE id=%s', (user_id, identifier))
            conn.execute('DELETE FROM guest_cart_items WHERE cart_id=%s', (identifier,))
    session.pop(SESSION_KEY, None)
    return adjusted
