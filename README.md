# omarchy-input-kit

Инструменты под конкретную машину: Omarchy 4.5 (Arch + Hyprland, Lua-конфиг),
мышь **Zelotes C-18** (`12c9:2003`, «SOAI USB Gaming Mouse») и клавиатура
**DEXP First Blood** (`1a2c:635a`, «SEMICO USB Keyboard»).

Три независимые части:

| Каталог | Задача | Что ставится |
|---|---|---|
| `lang-auto/` | английская раскладка при открытии терминала или меню Omarchy | `~/.local/bin/lang-auto`, user unit |
| `switcher/` | убрать конфликт `Shift+Pause` с DevTools в Chrome | сниппет для `~/.config/hypr/bindings.lua` |
| `devices/` | udev, keyd и документация по обеим устройствам | правило udev, шаблон keyd, docs |

Всё написано на python3 (stdlib) и bash. Внешние зависимости: `hyprctl`
(есть в Hyprland) и опционально `keyd`. В `/usr/share/omarchy/` ничего не
пишется.

## Быстрая установка

```bash
cd ~/projects/omarchy-input-kit

./install.sh                  # lang-auto + user unit, включает службу
./install.sh --with-switcher  # скопировать сниппет switcher (см. ниже)
./install.sh --with-udev      # правило udev для hidraw (sudo)
./install.sh --with-keyd      # конфиг keyd для мыши (sudo, если keyd есть)
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
```

Что именно проверяется:

- `lang-auto`: `python3 -m py_compile`, русская справка, `--once` на живом
  Hyprland, `--dry-run` без Traceback, unit-файл; состояние установленной
  службы выводится предупреждением.
- `switcher`: `hyprctl -j binds` показывает `SHIFT/ALT + PAUSE/BREAK` с
  release, press-дублей нет, `hyprctl -j configerrors` пуст.
- `devices`: `udevadm verify`, наличие `uaccess` для обоих id, шаблон keyd
  (`keyd check`, если keyd установлен), 3 интерфейса мыши и 2 клавиатуры.
  С `--live` ещё требуется ACL на `/dev/hidraw*`.

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
  устройств.
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

Установка системных файлов:

```bash
sudo install -Dm644 devices/udev/99-input-kit.rules /etc/udev/rules.d/99-input-kit.rules
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

**Снимок 4 — устройства и права.** Выполните:

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
- `keyd` в этом репозитории только шаблон; служба keyd не включается.

## Удаление

```bash
./install.sh --uninstall
./install.sh --uninstall --with-udev --with-keyd  # плюс системные файлы
```

`--uninstall` без флагов удаляет только `lang-auto`, user unit и
`~/.config/hypr/bindings.snippet.lua`. Ваш `bindings.lua` он не трогает.
