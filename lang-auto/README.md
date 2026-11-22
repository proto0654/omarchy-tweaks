# lang-auto

Демон для Omarchy 4.5: слушает event-сокет Hyprland и переключает клавиатуру
на английскую раскладку, когда открывается меню Omarchy (layer surface) или
новое окно терминала.

Целевая раскладка — первая из `input:kb_layout` (например, `us,ru` → `us`).
Если значение пустое, используется `us`.

## Установка

```bash
lang-auto/install.sh
```

Скрипт копирует `lang-auto` в `~/.local/bin/lang-auto`, ставит
`~/.config/systemd/user/lang-auto.service` и запускает службу:

```bash
systemctl --user daemon-reload
systemctl --user enable --now lang-auto.service
```

Повторный запуск безопасен (идемпотентность).

## Проверка

```bash
./verify.sh
```

Скрипт проверяет раскладки, клавиатуры, статус службы, event-сокет и
`--dry-run`. Итог: `ИТОГ: OK` или `ИТОГ: FAIL (N)`.

Ручная проверка:

```bash
~/.local/bin/lang-auto --once      # окружение и раскладки
~/.local/bin/lang-auto --dry-run   # что было бы переключено
journalctl --user -u lang-auto.service -f
```

## Флаги

```
lang-auto              демон (режим по умолчанию)
lang-auto --once       проверить окружение и выйти
lang-auto --dry-run    печатать «переключил бы на us (class=foot)», ничего не менять
lang-auto --verbose    журнал каждого события
lang-auto --help
```

## Удаление

```bash
lang-auto/install.sh --uninstall
```

## Как это работает

- Терминалы определяются по классу окна из `openwindow>>...` (подстрока,
  регистронезависимо): `foot`, `alacritty`, `kitty`, `wezterm`, `ghostty`.
- Меню — по namespace из `openlayer>>...`, если он содержит `menu` или
  `omarchy`.
- Перед переключением проверяется `active_keymap` в `hyprctl devices -j`:
  если раскладка уже английская, переключение не выполняется.
- При перезапуске Hyprland демон переподключается к сокету и продолжает
  работу.
