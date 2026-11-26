"""Перевод сообщений в ответах API без передачи внутренних ошибок клиенту."""
from .messages import language

ENGLISH = {
    'Сеанс завершён. Войдите снова.': 'Your session has expired. Sign in again.',
    'Для действия нужна другая учётная запись.': 'This account cannot perform that action.',
    'Укажите телефон в формате +7XXXXXXXXXX.': 'Enter a Russian phone number in the +7XXXXXXXXXX format.',
    'Доставка SMS ещё не подключена.': 'SMS delivery has not been configured.',
    'Слишком много попыток. Повторите вход через пять минут.': 'Too many attempts. Try again in five minutes.',
    'Логин или пароль неверен.': 'Incorrect username or password.',
    'Проверка завершена. Запросите новый код.': 'Verification has expired. Request a new code.',
    'Проверка относится к другому сеансу.': 'This verification belongs to another session.',
    'Неверный код подтверждения.': 'Incorrect verification code.',
    'Товар не найден.': 'Product not found.', 'Заказ не найден.': 'Order not found.', 'Размер не найден.': 'Size not found.',
    'Для покупки войдите как покупатель.': 'Sign in as a customer to make purchases.',
    'Сначала войдите в учётную запись.': 'Sign in first.',
    'Проверьте поля карточки товара.': 'Check the product fields.',
    'Не удалось прочитать фотографию.': 'The photo could not be read.',
    'Введите цену без знака рубля и не более чем с двумя знаками после точки.': 'Enter a price with at most two decimal places and no currency symbol.',
    'Цена должна быть больше нуля.': 'The price must be greater than zero.',
    'Фотография должна занимать не более 5 МБ.': 'The photo must not exceed 5 MB.',
    'Поддерживаются фотографии JPEG, PNG и WebP.': 'JPEG, PNG and WebP photos are supported.',
    'Размер сторон должен находиться между 32 и 4096 пикселями.': 'Photo dimensions must be between 32 and 4096 pixels.',
    'Сначала должна завершиться оплата заказа.': 'The order must be paid before completion.',
    'Сначала необходимо завершить отмену платежа или возврат денег.': 'Resolve the payment cancellation or refund first.',
}


def human(message):
    """Выбор понятного сообщения на языке текущего запроса."""
    return ENGLISH.get(message, message) if language.get() == 'en' else message
