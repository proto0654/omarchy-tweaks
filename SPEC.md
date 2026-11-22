# lang-auto — английская раскладка при открытии меню и терминалов

Утилита под Omarchy 4.5 (Arch + Hyprland, Lua-конфиг).

Проблема: после работы в русской раскладке при вызове меню Omarchy или открытии
нового терминала ввод приходит на русском — и первая же команда или поиск
превращаются в кашу. Нужно, чтобы в этих двух случаях ввод сразу был на
**английском** (первая раскладка из `input:kb_layout`, обычно `us`).

Никаких других задач в репозитории нет: ни устройств, ни хоткеев.

## Что должно быть

```
lang-auto/            каталог утилиты
  lang-auto           python3, stdlib, исполняемый
  install.sh          установка/удаление
  lang-auto.service   systemd user unit
  README.md           как поставить, как проверить
verify.sh             проверка на живой системе (в корне репо)
README.md             краткое описание репозитория
```

## Поведение

Демон читает event-сокет Hyprland:
`$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock`.

Реакции:

1. `openwindow>>ADDR,WORKSPACE,CLASS,TITLE` — если `CLASS` терминал
   (`foot`, `Alacritty`, `kitty`, `org.wezfurlong.wezterm`, `com.mitchellh.ghostty`,
   `ghostty`; сравнение регистронезависимое, по подстроке — Omarchy может
   запускать `footclient`), переключить раскладку на английскую.
2. `openlayer>>NAMESPACE` — если `NAMESPACE` содержит `menu` или `omarchy`
   (меню Omarchy — layer surface), тоже переключить на английскую.

Переключение:

- Целевую раскладку брать из `hyprctl -j getoption input:kb_layout`: первые
  символы до запятой (`us,ru` → `us`). Если значение пустое — `us`.
- Вызывать `hyprctl switchxkblayout all <имя>`. Если Hyprland не принял имя
  (rc != 0 или в stderr «Invalid»), повторить по индексу `0`.
- Перед вызовом проверить активную раскладку: `hyprctl devices -j`, поле
  `keyboards[].active_keymap`; если уже начинается на целевую (регистронезависимо) —
  ничего не делать (не дёргать переключение зря).
- Ошибки `hyprctl` писать в stderr один раз на класс события, не спамить.

## Флаги

```
lang-auto              демон (режим по умолчанию)
lang-auto --once       проверить окружение и выйти (сокет, hyprctl, раскладки)
lang-auto --dry-run    печатать «переключил бы на us (class=foot)», ничего не менять
lang-auto --verbose    журнал каждого события
lang-auto --help
```

## install.sh

- `install -m 755 lang-auto ~/.local/bin/lang-auto`
- ставит `~/.config/systemd/user/lang-auto.service`
  (`ExecStart=%h/.local/bin/lang-auto`, `Restart=on-failure`, `PartOf=graphical-session.target`,
  `After=graphical-session.target`)
- `systemctl --user daemon-reload && systemctl --user enable --now lang-auto.service`
- `--uninstall`: `systemctl --user disable --now`, удалить unit и бинарь.
- `set -euo pipefail`, `--help`, идемпотентность (повторный запуск не ломается).

## verify.sh (в корне)

Печатает по строке на проверку и итог:

1. `hyprctl -j getoption input:kb_layout` — раскладки читаются, первая непустая.
2. `hyprctl devices -j` — есть хотя бы одна клавиатура, печатает её `active_keymap`.
3. Демон в статусе `active` (`systemctl --user is-active lang-auto.service`).
4. Сокет существует по пути из `HYPRLAND_INSTANCE_SIGNATURE`.
5. `--dry-run` проходит без ошибок.

Итог: `ИТОГ: OK` или `ИТОГ: FAIL (N)`, код возврата 0/1.

## Требования к коду

- Python 3 stdlib only (`socket`, `json`, `subprocess`, `argparse`, `logging`).
- Переподключение к сокету, если Hyprland перезапустился (не падать, ждать и
  пробовать снова; в журнал одну строку).
- Русские комментарии и русские сообщения CLI. Английский — только имена
  классов окон, коды и имена переменных.
- Коммит: `feat: switch to english layout on omarchy menu and new terminals`.
