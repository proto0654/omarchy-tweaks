# omarchy-tweaks

Инструменты под конкретную машину: Omarchy 4.5 (Arch + Hyprland, Lua-конфиг),
мышь **Zelotes C-18** (`12c9:2003`, «SOAI USB Gaming Mouse») и клавиатура
**DEXP First Blood** (`1a2c:635a`, «SEMICO USB Keyboard»).

Три задачи, три каталога. Всё — python3 (stdlib) + bash, без внешних пакетов,
кроме `hyprctl` (есть всегда) и опционально `keyd`.

## 1. `lang-auto/` — английская раскладка на запуске

Хочу: когда открывается меню Omarchy или новое окно терминала, ввод сразу
переключается на **английский** (первая раскладка `kb_layout` = `us`).

Требования:

- Один python3-демон на stdlib, читает event-сокет Hyprland:
  `$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock`.
- Реагирует на события:
  - `openwindow>>ADDR,WORKSPACE,CLASS,TITLE` — если CLASS в списке терминалов
    (`foot`, `Alacritty`, `kitty`, `org.wezfurlong.wezterm`, `com.mitchellh.ghostty`,
    `ghostty`), переключить все клавиатуры на раскладку `us`.
  - `openlayer>>NAMESPACE` — если NAMESPACE содержит `menu` или `omarchy`
    (меню Omarchy — layer surface), тоже переключить на `us`.
- Переключение: `hyprctl switchxkblayout all us` — но сначала проверить
  фактическое имя раскладки через `hyprctl -j getoption input:kb_layout`
  (может быть `us,ru`; брать первый элемент) и `hyprctl devices -j`
  (`keyboards[].name`), чтобы работало и по имени, и по индексу. Ошибку
  `hyprctl` не глотать: писать в журнал один раз, не спамить каждое окно.
- Не переключать, если фокус уже в том же терминале/меню (не дёргать зря):
  сравнивать активную раскладку (`active_keymap`) перед вызовом.
- Флаги: `--once` (проверить один раз и выйти), `--dry-run` (печатать, что
  сделал бы), `--verbose`.
- Установка: `install.sh` кладёт скрипт в `~/.local/bin/lang-auto` и
  systemd user unit `lang-auto.service`, включает его (`systemctl --user
  enable --now`). Удаление: `install.sh --uninstall`.

## 2. `switcher/` — конфликт хоткея свитчера с браузером

- `bindings.snippet.lua` — `Shift+Pause` / `Shift+Break` меняет раскладку
  при отпускании, `Ctrl+Pause` меняет регистр при нажатии по кодам XKB
  Pause (`127`) и Break (`419`). Модификаторы сопоставляются точно.
- `conflicts.md` — объяснение конфликтов `Ctrl+Shift+C` в Chrome и Codex и
  причины выбора Ctrl: `Ctrl+Alt+V` активирует голосовой чат Hermes.
- `verify.sh` — проверка сочетаний и момента срабатывания в живом Hyprland,
  а также проверка ошибок конфигурации.

## 3. `devices/` — что реально умеют Zelotes C-18 и DEXP First Blood

Факты с этой машины (HID report descriptors, сняты из sysfs):

- Мышь `12c9:2003`, три интерфейса:
  - `hidraw0` — мышь, 5 кнопок + consumer `0x0238`;
  - `hidraw1` — **эмуляция клавиатуры**: полный набор keyboard usages
    (`0x00..0xC8`) + consumer-массив — джойстик и боковые кнопки шлют
    обычные клавиши (по умолчанию W/S/A/D/Space), значит маппятся любым
    evdev-инструментом;
  - `hidraw2` — vendor page `0xFF00` (настройка DPI/подсветки, протокол
    не документирован).
- Клавиатура `1a2c:635a`, два интерфейса:
  - `hidraw5` — boot-клавиатура (6KRO);
  - `hidraw6` — consumer + vendor `0xFF00/0x01` (подсветка RGB, 8 байт) +
    обычная клавиатура. `FN+F12` = калькулятор, `FN+F1..F12` = медиа.

Требования:

- `udev/99-input-kit.rules` — `uaccess` для hidraw обоих устройств, чтобы
  инструменты работали без root; `SUBSYSTEM=="hidraw"` по `ATTRS{idVendor}`,
  `ATTRS{idProduct}`.
- `keyd/zelotes-c18.conf` — шаблон пер-девайсного ремапа для keyd: секция
  `[zelotes-c18]` (`[ids]` → `12c9:2003`), примеры: джойстик вверх/вниз/влево/
  вправо → `up/down/left/right`, боковая кнопка → `macro`/`layer`. Комментарии
  по-русски, значения — реальные keyd-имена.
- `docs/dexp-first-blood.md` — подсветка (FN+SCROLL цикл, FN+стрелки
  яркость/скорость, FN+WIN блокировка Win), медиа-слой, что из этого работает
  без вендорского софта, что требует Windows-утилиты (нет Linux-аналога).
- `docs/zelotes-c18.md` — 11 кнопок, DPI 1500/2500/4000/7000/10000,
  джойстик = 5 клавиш, как проверить/переназначить, статус libratbag.

## Общие требования

- README.md: что за устройства, что ставится, как проверить каждую часть
  одной командой, скриншот-инструкция в тексте.
- Русские комментарии и русские сообщения CLI (английского в интерфейсе нет,
  кроме имён устройств и кодов клавиш).
- Ничего не трогать в `/usr/share/omarchy/`; только `~/.config`, `~/.local`.
- Каждый скрипт: `set -euo pipefail`, `--help`, `shellcheck`-чистый.
- Проверка: `bash verify.sh` в корне запускает все три проверки и печатает
  итог `OK/FAIL` по каждой части.
- Коммиты Conventional Commits, по-английски, коротко.
