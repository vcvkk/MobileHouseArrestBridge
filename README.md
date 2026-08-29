# MobileHouseArrest Bridge (PoC Test App)

Этот проект демонстрирует возможность использования эксплоита **MobileHouseArrest** в связке с компьютером (ПК / Mac) по схеме **Клиент – Сервер**.

---

## Архитектура решения

1. **iOS Companion (Сервер):**
   - Написан на Objective-C.
   - Подписан с идентификатором `com.apple.mobile.MobileHouseArrest`.
   - При запуске подгружает `/usr/lib/system/libsystem_containermanager.dylib`, обращается к `containermanagerd` и забирает токены расширения песочницы (`sandbox_extension_consume`) для запрашиваемых контейнеров (Class 2, Class 7, Class 13).
   - Поднимает TCP-сервер на порту `8080` для приема команд.

2. **PC Tool (`client.py`):**
   - Скрипт на Python, запускаемый на компьютере.
   - Подключается к iPhone по USB через проброшенный порт (`iproxy 8080 8080`).
   - Позволяет в интерактивном режиме с ПК вызывать активацию контейнеров, просматривать файлы (`ls`), скачивать (`get`) и перезаписывать (`put`) файлы.

---

## Инструкция по сборке и запуску

### Шаг 1. Сборка для iOS
Соберите бинарник или оберните его в приложение с помощью Xcode или Theos:
```bash
make
```

### Шаг 2. Подпись (Критически важный момент)
При упаковке в IPA укажите `CFBundleIdentifier` / `CodeDirectory Identifier`:
```text
com.apple.mobile.MobileHouseArrest
```
*Установите IPA на устройство с помощью TrollStore, Sideloadly или AltStore.*

### Шаг 3. Запуск и проброс порта по USB
1. Запустите приложение `MobileHouseArrestBridge` на iPhone.
2. На компьютере выполните команду проброса порта через `usbmuxd` / `libimobiledevice`:
```bash
iproxy 8080 8080
```

### Шаг 4. Управление с ПК через `client.py`

* **Проверка связи:**
```bash
python3 client.py ping
```

* **Активация доступа к контейнеру (например, приложению «Телефон»):**
```bash
python3 client.py activate --class-id 2 com.apple.mobilephone
```

* **Просмотр директории внутри полученного пути:**
```bash
python3 client.py ls /private/var/mobile/Containers/Data/Application/<UUID>/Library/Caches/
```

* **Скачивание файла на ПК:**
```bash
python3 client.py get /private/var/mobile/Containers/Data/Application/<UUID>/Documents/database.sqlite ./local_copy.sqlite
```

* **Заливка измененного файла с ПК на iPhone:**
```bash
python3 client.py put ./local_copy.sqlite /private/var/mobile/Containers/Data/Application/<UUID>/Documents/database.sqlite
```
