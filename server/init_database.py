"""Подготовка таблиц без изменения существующих товаров и заказов."""
from mobile_api.database import ROOT, connect

if __name__ == '__main__':
    with connect() as connection:
        for name in ('store.sql', 'mobile.sql'):
            connection.execute((ROOT / 'database' / name).read_text(encoding='utf-8'))
    print('Таблицы магазина и мобильных сеансов готовы. Существующие записи сохранены.')
