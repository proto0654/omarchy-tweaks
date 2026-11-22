# omarchy-input-kit

Утилита для Omarchy 4.5 (Arch + Hyprland, Lua-конфиг): при открытии меню
Omarchy и новых терминалов клавиатура сразу переключается на английскую
раскладку — первую из `input:kb_layout`.

Репозиторий содержит только `lang-auto` и её проверку. Подробности — в
[`lang-auto/README.md`](lang-auto/README.md) и [`SPEC.md`](SPEC.md).

## Быстрый старт

```bash
lang-auto/install.sh   # установить и запустить службу
./verify.sh            # проверить на живой системе
```

## Состав

```
lang-auto/
  lang-auto           демон (Python 3, stdlib)
  install.sh          установка/удаление
  lang-auto.service   systemd user unit
  README.md           установка и проверка
verify.sh             проверка на живой системе
```
