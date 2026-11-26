"""Каталог товаров и безопасное изменение карточек."""
from decimal import Decimal
from pathlib import Path
from uuid import uuid4
import io
import warnings
from PIL import Image, ImageOps
from .database import MEDIA_ROOT, connect, row, rows


def search(query='', brand='', model='', staff=False):
    """Поиск по названию, бренду и модели с параметрами SQL."""
    needle = '%' + query[:100].replace('!', '!!').replace('%', '!%').replace('_', '!_') + '%'
    products = rows('''SELECT p.*,COALESCE(SUM(v.stock),0) AS stock,
        COALESCE(MIN(COALESCE(v.price,p.price)) FILTER(WHERE v.stock>0),p.price) AS min_price
        FROM products p LEFT JOIN product_variants v ON v.product_id=p.id
        WHERE (%s OR p.is_active) AND (%s='' OR p.brand=%s) AND (%s='' OR p.model=%s)
        AND (p.name ILIKE %s ESCAPE '!' OR p.name_en ILIKE %s ESCAPE '!'
        OR p.model ILIKE %s ESCAPE '!' OR p.brand ILIKE %s ESCAPE '!')
        GROUP BY p.id ORDER BY p.id DESC LIMIT 100''',
        (staff, brand, brand, model, model, needle, needle, needle, needle))
    brands = [r['brand'] for r in rows('SELECT DISTINCT brand FROM products WHERE is_active ORDER BY brand')]
    models = [r['model'] for r in rows('SELECT DISTINCT model FROM products WHERE is_active AND (%s=%s OR brand=%s) ORDER BY model', (brand, '', brand))]
    return {'products': products, 'brands': brands, 'models': models}


def product(identifier, staff=False):
    """Получение карточки и доступных размеров с актуальными ценами."""
    item = row('SELECT * FROM products WHERE id=%s AND (%s OR is_active)', (identifier, staff))
    if not item:
        return None
    item['variants'] = rows('''SELECT v.id,v.size,v.stock,COALESCE(v.price,p.price) AS price,
        v.price AS custom_price FROM product_variants v JOIN products p ON p.id=v.product_id
        WHERE p.id=%s ORDER BY size''', (identifier,))
    return item


def money(value):
    """Проверка положительной цены с точностью до копеек."""
    import re
    if not re.fullmatch(r'[0-9]{1,8}(\.[0-9]{1,2})?', value):
        raise ValueError('Введите цену без знака рубля и не более чем с двумя знаками после точки.')
    result = Decimal(value)
    if result <= 0:
        raise ValueError('Цена должна быть больше нуля.')
    return result


def save(identifier, fields, photo=None):
    """Сохранение карточки без изменения резервов оформленных заказов."""
    values = (fields['name'], fields['name_en'], fields['brand'], fields['model'],
        fields['description'], fields['description_en'], money(fields['price']), fields['is_active'])
    with connect() as connection:
        if identifier:
            item = connection.execute('''UPDATE products SET name=%s,name_en=%s,brand=%s,model=%s,
                description=%s,description_en=%s,price=%s,is_active=%s,
                photo=COALESCE(%s,photo),cache_version=cache_version+1 WHERE id=%s RETURNING id''',
                (*values, photo, identifier)).fetchone()
            if not item:
                raise ValueError('Товар не найден.')
        else:
            item = connection.execute('''INSERT INTO products
                (name,name_en,brand,model,description,description_en,price,is_active,photo)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s) RETURNING id''',
                (*values, photo or '/static/products/photo-city.png')).fetchone()
            connection.execute('INSERT INTO product_variants(product_id,size) SELECT %s,generate_series(36,46)', (item['id'],))
        return item['id']


def upload_photo(data):
    """Проверка фотографии и сохранение в WebP с уникальным именем."""
    if len(data) > 5 * 1024 * 1024:
        raise ValueError('Фотография должна занимать не более 5 МБ.')
    with warnings.catch_warnings():
        warnings.simplefilter('error', Image.DecompressionBombWarning)
        with Image.open(io.BytesIO(data)) as probe:
            if probe.format not in ('JPEG', 'PNG', 'WEBP') or getattr(probe, 'n_frames', 1) != 1:
                raise ValueError('Поддерживаются фотографии JPEG, PNG и WebP.')
            if not all(32 <= side <= 4096 for side in probe.size):
                raise ValueError('Размер сторон должен находиться между 32 и 4096 пикселями.')
            probe.verify()
    with Image.open(io.BytesIO(data)) as source:
        image = ImageOps.exif_transpose(source).convert('RGB')
        image.thumbnail((1600, 1600))
        directory = MEDIA_ROOT / 'uploads'
        directory.mkdir(parents=True, exist_ok=True)
        name = uuid4().hex + '.webp'
        image.save(directory / name, 'WEBP', quality=85, method=4)
        return '/static/uploads/' + name
