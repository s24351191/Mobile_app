"""Правила корзины, заказов и баллов с расчётом денежных сумм через Decimal."""

from .messages import t, product_name

from decimal import Decimal, ROUND_FLOOR
import os

from .database import connect, row, rows


def whole(value):
    """Получение целого количества баллов без дробной части."""
    return int(value.to_integral_value(rounding=ROUND_FLOOR))


def points_limit(subtotal, balance):
    """Расчёт доступной скидки в пределах баланса и 30 процентов стоимости."""
    return min(balance, whole(subtotal * Decimal("0.30")))


def cart(user_id):
    """Чтение корзины с текущими ценами товаров."""
    items = rows(
        """SELECT c.variant_id, c.quantity, v.size, v.stock,
        p.id AS product_id, p.name, p.name_en, p.model, p.photo,
        COALESCE(v.price,p.price) AS price, p.is_active,
        COALESCE(v.price,p.price) * c.quantity AS line_total
        FROM cart_items c JOIN product_variants v ON v.id = c.variant_id
        JOIN products p ON p.id = v.product_id
        WHERE c.user_id = %s ORDER BY c.variant_id""",
        (user_id,),
    )
    subtotal = sum(
        (item["line_total"] for item in items), Decimal("0.00")
    )
    user = row(
        "SELECT points_balance FROM users WHERE id = %s", (user_id,)
    )
    return {
        "items": items,
        "subtotal": subtotal,
        "max_points": points_limit(subtotal, user["points_balance"]),
    }


def change_cart(user_id, variant_id, quantity, add=False):
    """Изменение корзины с блокировкой пользователя."""
    if not 0 <= quantity <= 99:
        raise ValueError(t('errors.quantity_range'))
    with connect() as conn:
        conn.execute(
            "SELECT id FROM users WHERE id = %s FOR UPDATE", (user_id,)
        )
        old = conn.execute(
            "SELECT quantity FROM cart_items WHERE user_id=%s AND variant_id=%s",
            (user_id, variant_id),
        ).fetchone()
        quantity += old["quantity"] if add and old else 0
        if quantity == 0:
            conn.execute(
                "DELETE FROM cart_items WHERE user_id=%s AND variant_id=%s",
                (user_id, variant_id),
            )
            return
        variant = conn.execute(
            """SELECT v.stock, p.is_active FROM product_variants v
            JOIN products p ON p.id=v.product_id WHERE v.id=%s""",
            (variant_id,),
        ).fetchone()
        if not variant or not variant["is_active"]:
            raise ValueError(t('errors.product_unavailable'))
        if quantity > 99 or quantity > variant["stock"]:
            raise ValueError(
                t('errors.insufficient_stock')
            )
        conn.execute(
            """INSERT INTO cart_items (user_id,variant_id,quantity) VALUES (%s,%s,%s)
            ON CONFLICT (user_id,variant_id) DO UPDATE SET quantity=EXCLUDED.quantity""",
            (user_id, variant_id, quantity),
        )


def checkout(user_id, token, recipient, address, points):
    """Создание заказа с блокировкой баланса и остатков в одной транзакции."""
    if not token or len(token) > 100:
        raise ValueError(t('errors.cart_refresh_required'))
    if not 2 <= len(recipient) <= 100 or not 5 <= len(address) <= 300:
        raise ValueError(
            t('errors.recipient_fields')
        )
    if points < 0:
        raise ValueError(
            t('errors.negative_points')
        )
    with connect() as conn:
        user = conn.execute(
            "SELECT * FROM users WHERE id=%s FOR UPDATE", (user_id,)
        ).fetchone()

        existing = conn.execute(
            "SELECT id,user_id FROM orders WHERE checkout_token=%s",
            (token,),
        ).fetchone()
        if existing:
            if existing["user_id"] != user_id:
                raise ValueError(t('errors.refresh_cart'))
            return existing["id"]
        items = conn.execute(
            """SELECT c.quantity,v.id AS variant_id,v.size,v.stock,
            p.name,p.name_en,p.model,COALESCE(v.price,p.price) AS price,
            p.photo,p.is_active FROM cart_items c
            JOIN product_variants v ON v.id=c.variant_id JOIN products p ON p.id=v.product_id
            WHERE c.user_id=%s ORDER BY v.id FOR UPDATE OF v,p""",
            (user_id,),
        ).fetchall()
        if not items:
            raise ValueError(t('cart.empty'))
        for item in items:
            if (
                not item["is_active"]
                or item["quantity"] > item["stock"]
            ):
                raise ValueError(
                    t('errors.product_quantity', value0=product_name(item), value1=item['size'])
                )
        subtotal = sum(
            (i["price"] * i["quantity"] for i in items), Decimal("0.00")
        )
        limit = points_limit(subtotal, user["points_balance"])
        if points > limit:
            raise ValueError(
                t('errors.points_limit', value0=limit)
            )
        order = conn.execute(
            """INSERT INTO orders
            (user_id,checkout_token,recipient_name,address,subtotal,points_spent,total)
            VALUES (%s,%s,%s,%s,%s,%s,%s) RETURNING id""",
            (
                user_id,
                token,
                recipient,
                address,
                subtotal,
                points,
                subtotal - points,
            ),
        ).fetchone()
        if os.getenv('PAYMENTS_ENABLED', 'false').lower() == 'true':

            conn.execute('UPDATE orders SET payment_required=TRUE WHERE id=%s', (order['id'],))
        for item in items:
            conn.execute(
                """INSERT INTO order_items
                (order_id,variant_id,name,name_en,model,size,quantity,unit_price,photo) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
                (
                    order["id"],
                    item["variant_id"],
                    item["name"],
                    item["name_en"],
                    item["model"],
                    item["size"],
                    item["quantity"],
                    item["price"],
                    item["photo"],
                ),
            )
            conn.execute(
                "UPDATE product_variants SET stock=stock-%s WHERE id=%s",
                (item["quantity"], item["variant_id"]),
            )
        if points:
            conn.execute(
                "UPDATE users SET points_balance=points_balance-%s WHERE id=%s",
                (points, user_id),
            )
            conn.execute(
                "INSERT INTO points_ledger (user_id,order_id,kind,amount) VALUES (%s,%s,'spend',%s)",
                (user_id, order["id"], -points),
            )
        conn.execute(
            "DELETE FROM cart_items WHERE user_id=%s", (user_id,)
        )
        return order["id"]


def transition_order(order_id, target, owner_id=None):
    """Смена состояния заказа с проверкой прав и возвратом резерва."""
    if target not in ("accepted", "rejected", "completed", "cancelled"):
        raise ValueError(t('errors.order_status'))
    if owner_id is not None and target != 'cancelled':
        raise ValueError(t('errors.order_staff_action'))
    with connect() as conn:
        owner = conn.execute(
            "SELECT user_id FROM orders WHERE id=%s", (order_id,)
        ).fetchone()
        if not owner or (
            owner_id is not None and owner_id != owner["user_id"]
        ):
            raise ValueError(t('errors.order_not_found'))

        conn.execute(
            "SELECT id FROM users WHERE id=%s FOR UPDATE",
            (owner["user_id"],),
        )
        order = conn.execute(
            "SELECT * FROM orders WHERE id=%s FOR UPDATE", (order_id,)
        ).fetchone()
        if order["status"] == target:
            return

        if owner_id is not None and order["status"] == "accepted":
            raise ValueError(t('errors.order_customer_cancel_locked'))
        allowed = {
            "accepted": {"new"},
            "rejected": {"new"},
            "completed": {"accepted"},
            "cancelled": {"new", "accepted"},
        }
        if order["status"] not in allowed[target]:
            if target == "completed" and order["status"] == "new":
                raise ValueError(t('errors.order_accept_first'))
            raise ValueError(t('errors.order_not_editable'))
        if order.get('payment_required'):
            from .payments import guard_transition
            guard_transition(conn, order, target)
        if target == "accepted":
            conn.execute("UPDATE orders SET status='accepted' WHERE id=%s", (order_id,))
            return
        if target == "completed":
            earned = whole(order["total"] * Decimal("0.05"))
            conn.execute(
                "UPDATE orders SET status=%s,points_earned=%s WHERE id=%s",
                (target, earned, order_id),
            )
            if earned:
                conn.execute(
                    "UPDATE users SET points_balance=points_balance+%s WHERE id=%s",
                    (earned, order["user_id"]),
                )
                conn.execute(
                    "INSERT INTO points_ledger (user_id,order_id,kind,amount) VALUES (%s,%s,'earn',%s)",
                    (order["user_id"], order_id, earned),
                )
        else:
            items = conn.execute(
                "SELECT variant_id,quantity FROM order_items WHERE order_id=%s ORDER BY variant_id",
                (order_id,),
            ).fetchall()
            for item in items:
                conn.execute(
                    "UPDATE product_variants SET stock=stock+%s WHERE id=%s",
                    (item["quantity"], item["variant_id"]),
                )
            if order["points_spent"]:
                conn.execute(
                    "UPDATE users SET points_balance=points_balance+%s WHERE id=%s",
                    (order["points_spent"], order["user_id"]),
                )
                conn.execute(
                    "INSERT INTO points_ledger (user_id,order_id,kind,amount) VALUES (%s,%s,'refund',%s)",
                    (order["user_id"], order_id, order["points_spent"]),
                )
            conn.execute(
                "UPDATE orders SET status=%s WHERE id=%s",
                (target, order_id),
            )
