"""Защита состояний заказов, для которых уже предусмотрена оплата."""


def guard_transition(connection, order, target):
    """Проверка завершения оплаты или возврата перед сменой состояния."""
    payment = connection.execute(
        'SELECT * FROM payments WHERE order_id=%s ORDER BY created_at DESC,id DESC LIMIT 1',
        (order['id'],),
    ).fetchone()
    if target == 'completed' and (
        not payment or payment['status'] != 'succeeded' or payment['refund_status'] != 'none'
    ):
        raise ValueError('Сначала должна завершиться оплата заказа.')
    if target in ('cancelled', 'rejected') and payment:
        if payment['status'] != 'cancelled' and payment['refund_status'] != 'succeeded':
            raise ValueError('Сначала необходимо завершить отмену платежа или возврат денег.')
