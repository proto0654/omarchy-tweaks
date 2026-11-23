# omarchy-tweaks

Твики под конкретную машину: Omarchy 4.5 (Arch + Hyprland, Lua-конфиг), мышь
**Zelotes C-18** (`12c9:2003`, «SOAI USB Gaming Mouse») и клавиатура
**DEXP First Blood** (`1a2c:635a`, «SEMICO USB Keyboard»).

Один репозиторий на все локальные правки рабочего стола: каждая часть — свой
каталог со своим `install.sh`/`verify.sh`, общие скрипты в корне прогоняют их
все. Части независимы: можно поставить одну.

Четыре части:

| Каталог | Задача | Что ставится |
|---|---|---|
| `lang-auto/` | английская раскладка при открытии терминала или меню Omarchy | `~/.local/bin/lang-auto`, user unit |
| `switcher/` | убрать конфликт `Shift+Pause` с DevTools в Chrome | сниппет для `~/.config/hypr/bindings.lua` |
| `devices/` | udev, keyd и документация по обеим устройствам | правило udev, шаблон keyd, docs |
| `apps-by-usage/` | сетка «Приложения» в стартовом меню: сортировка по частоте запусков | клон плагина `omarchy.dock` + два патча |

Всё написано на python3 (stdlib) и bash. Внешние зависимости: `hyprctl`
(есть в Hyprland) и опционально `keyd`. В `/usr/share/omarchy/` ничего не
пишется.

## Быстрая установка

```bash
cd ~/projects/omarchy-tweaks

./install.sh                  # lang-auto + user unit, включает службу
./install.sh --with-switcher  # скопировать сниппет switcher (см. ниже)
./install.sh --with-udev      # правило udev для hidraw (sudo)
./install.sh --with-keyd      # конфиг keyd для мыши (sudo, если keyd есть)
./install.sh --with-apps      # сортировка «Приложений» по частоте (клон дока)
```

`install.sh` понимает `--dry-run`, `--uninstall` и `--help`. Системные файлы
(`/etc/udev/rules.d`, `/etc/keyd`) ставятся только с явными флагами
`--with-udev`/`--with-keyd`.

### switcher: сниппет не подключается сам

`switcher/bindings.snippet.lua` — это **замена** четырёх press-строк, а не
дополнительный файл. Если просто подключить его рядом со старыми привязками,
сработают и press, и release. Поэтому:

1. Откройте `~/.config/hypr/bindings.lua`.
2. Найдите строки `SHIFT + PAUSE`, `SHIFT + BREAK`, `ALT + PAUSE`,
   `ALT + BREAK` и замените их блоком из
   `~/.config/hypr/bindings.snippet.lua`.
3. Выполните `hyprctl reload`.

После этого `bash switcher/verify.sh` увидит четыре привязки с
`"release": true` и не найдёт press-дублей.

## Проверка одной командой

```bash
bash verify.sh          # все три части, итог OK/FAIL по каждой
bash verify.sh --live   # плюс строгая проверка uaccess-ACL для devices
```

По отдельности:

```bash
bash lang-auto/verify.sh
bash switcher/verify.sh
bash devices/verify.sh
bash apps-by-usage/verify.sh -v
```

Что именно проверяется:

- `lang-auto`: `python3 -m py_compile`, русская справка, `--once` на живом
  Hyprland, `--dry-run` без Traceback, unit-файл; состояние установленной
  службы выводится предупреждением.
- `switcher`: `hyprctl -j binds` показывает `SHIFT/ALT + PAUSE/BREAK` с
  release, press-дублей нет, `hyprctl -j configerrors` пуст.
- `devices`: `udevadm verify`, наличие `uaccess` для обоих id, шаблон keyd
  (`keyd check`, если keyd установлен), 3 интерфейса мыши; у клавиатуры —
  минимум один hidraw и живое event-устройство, отсутствие второго
  (consumer/vendor) печатается предупреждением с причиной из ядра.
  С `--live` ещё требуется ACL на `/dev/hidraw*`.
- `apps-by-usage`: клон плагина на месте, оба патча наложены, в манифесте есть
  kind `menu`, клон включён, стоковый `omarchy.dock` выключен. С `-v` печатает
  верх журнала запусков.

## 1. lang-auto

Демон читает `$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock`
(если сигнатура устарела — ищет самый свежий живой сокет) и реагирует на:

- `openwindow>>ADDR,WORKSPACE,CLASS,TITLE` — если `CLASS` — терминал из
  списка (`foot`, `Alacritty`, `kitty`, `org.wezfurlong.wezterm`,
  `com.mitchellh.ghostty`, `ghostty`; сравнение по подстроке без учёта
  регистра, чтобы ловить `footclient`);
- `openlayer>>NAMESPACE` — если в `NAMESPACE` есть `menu` или `omarchy`.

Перед переключением демон читает `hyprctl -j getoption input:kb_layout`
(берёт первый элемент, на этой машине `us`) и `hyprctl -j devices`. Если все
клавиатуры уже на нужной раскладке, `hyprctl switchxkblayout` не вызывается.
Переключение идёт по индексу раскладки (`all <index>`), потому что Hyprland
на этой машине не принимает имя раскладки в `switchxkblayout`. Одинаковые
ошибки `hyprctl` пишутся в журнал один раз, а не на каждое окно.

```bash
lang-auto --once      # проверить сокет, hyprctl и раскладки, выйти
lang-auto --dry-run   # показать, что было бы переключено
lang-auto --verbose   # подробный журнал
```

Служба:

```bash
systemctl --user status lang-auto.service
journalctl --user -u lang-auto.service -f
```

Установка и удаление:

```bash
bash lang-auto/install.sh
bash lang-auto/install.sh --uninstall
```

Подробности: `lang-auto/README.md`.

## 2. switcher

Симптом: в Google Chrome под XWayland `Shift+Pause` (свитчер `text-conv`)
открывает DevTools. `text-conv` копирует выделение через `wtype`, инжектируя
`Ctrl+C`; если физический `Shift` ещё зажат, Chrome получает `Ctrl+Shift+C` —
«Inspect element».

Что сделано:

- `bindings.snippet.lua` переносит четыре хоткея на **release** (с
  `ignore_mods`, иначе release может не сработать после отпускания Shift);
- `conflicts.md` — таблица горячих клавиш Chrome и вывод: DevTools должен
  открываться только по `F12`;
- `verify.sh` — проверка живого Hyprland.

Подробности и таблица: `switcher/conflicts.md`.

## 3. devices

### Zelotes C-18

Три HID-интерфейса: `hidraw0` — мышь (5 кнопок + consumer `0x0238`),
`hidraw1` — эмуляция клавиатуры (джойстик и боковые кнопки шлют обычные
клавиши, по умолчанию `W/S/A/D/Space`), `hidraw2` — vendor page `0xFF00`
(DPI/подсветка, протокол не документирован).

- udev: `devices/udev/99-input-kit.rules` даёт `uaccess` на hidraw обоих
  устройств (имя файла историческое — чтобы не переустанавливать правило
  в `/etc/udev/rules.d`, оно осталось прежним).
- keyd: `devices/keyd/zelotes-c18.conf` — пер-девайсный ремап для
  `12c9:2003`. Джойстик переводится в стрелки, боковая кнопка удерживает слой
  `zelotes-c18`, вторая — макрос.
- Подробно: `devices/docs/zelotes-c18.md` (11 кнопок, DPI
  1500/2500/4000/7000/10000, проверка, статус libratbag).

### DEXP First Blood

Два интерфейса: `hidraw5` — boot-клавиатура (6KRO), `hidraw6` — consumer,
vendor `0xFF00/0x01` (RGB, 8 байт) и клавиатура. `FN+F12` — калькулятор,
`FN+F1..F12` — медиа.

Подробно: `devices/docs/dexp-first-blood.md` (медиа-слой, подсветка
`FN+SCROLL`, яркость/скорость `FN+стрелки`, блокировка Win `FN+WIN`, что
работает без вендорского софта).

Второй интерфейс (`…:1.1`, `protocol Mouse` — там же consumer-канал и RGB)
поднимается не всегда: `usbhid` срывается на чтении HID-дескриптора
(`can't add hid device: -110`, `probe with driver usbhid failed with error
-71`), драйвер к интерфейсу не привязывается, и hidraw у него не появляется.
Клавиатура при этом работает целиком через первый интерфейс (hidraw +
event-устройство), недоступен только вендорный канал, протокол которого всё
равно не документирован. Поэтому `devices/verify.sh` в этом случае пишет
предупреждение с причиной из `journalctl -k`, а не FAIL.

Вернуть второй узел: переподключить клавиатуру в другой порт (лучше USB2) и
посмотреть `ls /sys/class/hidraw/`, либо вручную:

```bash
echo 1-5:1.1 | sudo tee /sys/bus/usb/drivers/usbhid/bind
```

Установка системных файлов:

```bash
sudo install -Dm644 devices/udev/99-input-kit.rules /etc/udev/rules.d/99-input-kit.rules  # имя прежнее, см. выше
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=hidraw

sudo install -Dm644 devices/keyd/zelotes-c18.conf /etc/keyd/zelotes-c18.conf
sudo keyd reload
```

Без root после udev-правила:

```bash
evtest /dev/input/by-id/usb-SOAI_USB_Gaming_Mouse-if01-event-kbd
evtest /dev/input/by-id/usb-SEMICO_USB_Keyboard-if01-event-kbd
```

## 4. apps-by-usage

Задача: в стартовом меню (`SUPER+SPACE` → «Приложения») сетка всегда шла по
алфавиту, и нужные приложения приходилось каждый раз искать.

Что сделано:

- стоковый плагин дока клонируется в `~/.config/omarchy/plugins/${USER}.dock`;
- `AppGrid.qml`: при пустом поле поиска плитки идут по числу запусков **из этой
  же сетки** — не по глобальной статистике окон и не по запускам из дока.
  Первая плитка — самая частая, а фокус при открытии и так стоит на первой.
  Как только начинаешь печатать, порядок снова по релевантности запроса;
- `Dock.qml`: клон живёт в scoped-shell без `appLibrary` и без `shellConfig`,
  поэтому в манифесте добавлен kind `menu` (только с ним шелл выдаёт клону
  app library через прокси), а секцию `dock` из `~/.config/omarchy/shell.json`
  клон читает сам — `omarchy dock` и правки файла подхватываются на лету;
- журнал запусков: `~/.local/state/omarchy/app-launch-usage`, одна строка =
  одно нажатие. Удалить файл — счётчики обнулятся.

```bash
bash apps-by-usage/install.sh     # клон + патчи + kind menu + рестарт шелла
bash apps-by-usage/verify.sh -v   # проверка и текущий верх журнала
bash apps-by-usage/seed.sh        # стартовые счётчики, если журнал пуст
```

В `/usr/share/omarchy/` ничего не пишется: правка пакета была бы затёрта
обновлением. Откат к штатной сетке:

```bash
omarchy plugin remove ${USER}.dock
```

Ограничение: клон — это снимок дока на момент установки. Правки дока из
обновлений Omarchy в клон сами не попадают: после крупного обновления
посмотрите `bash apps-by-usage/install.sh` (он переклонирует при отсутствии
клона) и при необходимости обновите патчи из `apps-by-usage/*.patch`.

## Скриншот-проверка (что должно быть видно)

Это текстовые «скриншоты»: команда и ожидаемая картинка. Реальные снимки
экрана можно сделать в любой момент, они не нужны для работы.

**Снимок 1 — терминал на английском.** Откройте новый терминал (`SUPER+Return`)
и выполните:

```bash
hyprctl -j devices | grep -m1 active_keymap
```

Ожидается `"active_keymap": "English (US)"`. В меню Omarchy (`SUPER`) ввод
тоже должен идти латиницей.

**Снимок 2 — журнал lang-auto.** В терминале:

```bash
journalctl --user -u lang-auto.service -n 5 --no-pager
```

Ожидается строка вида `переключил на us` или
`раскладка уже us` и отсутствие повторяющихся ошибок `hyprctl` на каждое окно.

**Снимок 3 — release-хоткеи.** Выполните:

```bash
hyprctl -j binds | python3 -m json.tool | grep -A2 '"key": "PAUSE"'
```

У четырёх нужных привязок (Shift/Alt × PAUSE/BREAK) должно быть
`"release": true`. Затем откройте Chrome, выделите слово, нажмите
`Shift+Pause`: текст меняет раскладку, DevTools не открывается. `F12`
по-прежнему открывает DevTools — это ожидаемо.

**Снимок 4 — сетка «Приложений».** `SUPER+SPACE` → «Приложения». Верхние
плитки — те, что чаще всего запускались из этой сетки, курсор стоит на первой.
`bash apps-by-usage/verify.sh -v` показывает те же счётчики в терминале.

**Снимок 5 — устройства и права.** Выполните:

```bash
bash devices/verify.sh --live
getfacl -p /dev/hidraw0
```

Ожидается `devices: OK` и ACL-строка `user:proto:rw-` (ваш пользователь)
на hidraw-узлах. Если ACL нет — правило udev не установлено или устройство
не переподключено.

## Ограничения

- `lang-auto` не переключает раскладку для уже открытых окон: он реагирует
  только на события `openwindow`/`openlayer`. `--once` проверяет окружение
  (сокет, `hyprctl`, раскладки), а не текущий фокус.
- Слой с `omarchy` в имени — это не только меню, но и bar/dock/notifications.
  Так требует SPEC; на практике раскладка может переключиться и при открытии
  такого слоя.
- DPI, подсветка и макросы Zelotes/DEXP на уровне прошивки не настраиваются
  из Linux: вендорные протоколы не документированы, libratbag эту мышь не
  поддерживает.
- У DEXP второй HID-интерфейс (consumer/vendor) может не подняться вовсе
  (`usbhid` -110/-71): клавиатура работает, вендорный канал/RGB недоступен,
  отдельного hidraw для него нет.
- `keyd` в этом репозитории только шаблон; служба keyd не включается.
- `apps-by-usage` считает только запуски из сетки «Приложения». Запуск с дока,
  из меню поиском или из терминала счётчик не увеличивает — так и задумано:
  сортировка отражает привычки именно в этом меню.
- Клон дока — снимок на момент установки: обновления Omarchy в него не
  приезжают, пока патчи не обновлены вручную.

## Удаление

```bash
./install.sh --uninstall
./install.sh --uninstall --with-apps              # плюс вернуть штатный док
./install.sh --uninstall --with-udev --with-keyd  # плюс системные файлы
```

`--uninstall` без флагов удаляет только `lang-auto`, user unit и
`~/.config/hypr/bindings.snippet.lua`. Ваш `bindings.lua` он не трогает.
