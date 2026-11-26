"""Короткие сообщения сервера на языке запроса."""
from contextvars import ContextVar
from pathlib import Path
import json

language = ContextVar('language', default='ru')
catalogs = {
    code: json.loads(Path(__file__).with_name(code + '.json').read_text(encoding='utf-8'))
    for code in ('ru', 'en')
}


def t(key, **values):
    """Получение сообщения и подстановка значений."""
    value = catalogs[language.get()].get(key, key)
    return value.format(**values) if values else value


def product_name(product):
    """Выбор названия товара для текущего языка."""
    return product.get('name_en') or product['name'] if language.get() == 'en' else product['name']
