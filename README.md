# PARA — учебное приложение магазина обуви

Учебный проект магазина обуви «PARA». Состоит из мобильного приложения на **Flutter**,
серверной части на **FastAPI** и базы данных **PostgreSQL**. Проект лежит в `C:\mobile_app`.

## Структура папок

- `app` — мобильное приложение Flutter.
- `server` — серверная часть:
  - `mobile_api` — код API на FastAPI;
  - `database` — SQL-скрипты;
  - `tests` — тесты сервера.
- `images` — картинки товаров.
- `docs` — методичка и страницы с кодом.
- `tools` — инструменты (Flutter, Android Studio, Android SDK, Gradle).

## Что нужно установить

- **Flutter 3.47.9** — распаковать в `C:\mobile_app\tools\flutter`.
- **Android Studio** — в `C:\mobile_app\tools\android-studio`.
- **Android SDK API 36** и **NDK 28.2.13676358**.
- **Эмулятор Pixel 6 API 36** (создаётся в Device Manager).
- **Python 3.13 или новее**.
- **PostgreSQL 18 и pgAdmin**.

## Первая настройка

1. В **pgAdmin** создайте базу данных `shoe_store`.

2. Скопируйте `server\.env.example` в `server\.env` и заполните его:


Copy-Item C:\mobile_app\server\.env.example C:\mobile_app\server\.env


В файле `server\.env` укажите:
- `DATABASE_URL` — строку подключения с вашим паролем вместо `ВАШ_ПАРОЛЬ`, например:
  `postgresql://postgres:ВАШ_ПАРОЛЬ@localhost:5432/shoe_store`;
- `MEDIA_ROOT=C:/mobile_app/server/media`;
- `SECRET_KEY` — сгенерируйте командой:


python -c "import secrets; print(secrets.token_hex(32))"


3. Создайте папку `server\media\products` и положите туда файл `photo-city.png`:


New-Item -ItemType Directory -Force C:\mobile_app\server\media\products
Copy-Item C:\mobile_app\images\photo-city.png C:\mobile_app\server\media\products\photo-city.png


4. Настройте сервер:


cd C:\mobile_app\server
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
python init_database.py


5. Настройте приложение:


cd C:\mobile_app\app
flutter pub get


## Запуск проекта

**Терминал 1 — сервер:**


cd C:\mobile_app\server
.\.venv\Scripts\Activate.ps1
python -m mobile_api


Проверка сервера:


Invoke-RestMethod http://127.0.0.1:8001/v1/health


**Эмулятор:** запустите эмулятор Pixel 6 API 36 в Android Studio через Device Manager
и проверьте, что он виден:


flutter devices


**Терминал 2 — приложение:**


cd C:\mobile_app\app
flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:8001/v1


Адрес `10.0.2.2` — это адрес компьютера внутри эмулятора Android, поэтому приложение
обращается к серверу, запущенному на вашем компьютере.

## Тесты

**Тесты приложения** (из папки `app`), ожидается `All tests passed`:


cd C:\mobile_app\app
flutter test


**Тесты сервера** (из папки `server` с активным `.venv`, в `.env` должно быть `DEMO_AUTH=true`),
ожидается `14 passed`:


cd C:\mobile_app\server
.\.venv\Scripts\Activate.ps1
python run_tests.py


**Интеграционный тест.** В одном терминале запустите демо-сервер (порт 8015, если занят —
добавьте `--port 8016`):


cd C:\mobile_app\server
.\.venv\Scripts\Activate.ps1
python run_demo.py


Проверка:


Invoke-RestMethod http://127.0.0.1:8015/v1/health


В другом терминале из папки `app` запустите интеграционный тест:


cd C:\mobile_app\app
flutter test integration_test/purchase_test.dart -d emulator-5554


Если демо-сервер запущен на порту 8016, добавьте параметр:


cd C:\mobile_app\app
flutter test integration_test/purchase_test.dart -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:8016/v1


По окончании остановите `run_demo.py` через **Ctrl+C**.

## Типичные проблемы

- `flutter` не найден в PATH → откройте новый терминал после Reload Window.
- `(.venv)` не активно → возникает `ModuleNotFoundError`.
- Пустой каталог → проверьте, что сервер запущен и в базе есть товары.
- Ошибка пароля PostgreSQL → проверьте `DATABASE_URL` в `.env`.
- Gradle падает из-за памяти → закройте лишние программы, уменьшите `org.gradle.jvmargs` в `app\android\gradle.properties`.

## Демо-доступы

- Покупатель: вход по телефону с кодом `123456`.
- Сотрудник: логин `admin`, пароль `Admin12345!`, SMS-код `654321`.

Это учебные значения из методички при `DEMO_AUTH=true`.
