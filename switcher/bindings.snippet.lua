-- Хоткеи правки выделенного текста на отпускание клавиши, а не на нажатие.
--
-- Почему release, а не press:
--   text-conv копирует выделение через wtype, инжектируя Ctrl+C. Если обработчик
--   срабатывает в момент нажатия Shift+Pause, физический Shift ещё зажат, и
--   Chrome под XWayland получает Ctrl+Shift+C — «Inspect element».
--   Привязка к отпусканию даёт шанс, что Shift уже отпущен; сам text-conv тоже
--   отпускает модификаторы перед инъекцией (wtype -m shift -m ctrl ...).
--   Это не отменяет правило: свитчер не должен посылать Ctrl+Shift+I/J/M.
--
-- ignore_mods нужен, потому что к моменту отпускания Pause маска модификаторов
-- уже может измениться (Shift отпущен раньше). Без него Hyprland просто не
-- увидит release-привязку.
--
-- Замените этими строками press-варианты в ~/.config/hypr/bindings.lua,
-- затем выполните: hyprctl reload
--
-- На клавише Pause с Shift XKB выдаёт keysym BREAK, поэтому дублируем оба имени.
o.bind("SHIFT + PAUSE", "Сменить раскладку выделенного", "/home/proto/.local/bin/text-conv layout", { release = true, ignore_mods = true })
o.bind("SHIFT + BREAK", "Сменить раскладку выделенного", "/home/proto/.local/bin/text-conv layout", { release = true, ignore_mods = true })
o.bind("ALT + PAUSE", "Инвертировать регистр выделенного", "/home/proto/.local/bin/text-conv case", { release = true, ignore_mods = true })
o.bind("ALT + BREAK", "Инвертировать регистр выделенного", "/home/proto/.local/bin/text-conv case", { release = true, ignore_mods = true })
