-- Shift+Pause — смена раскладки выделения, Ctrl+Pause — инверсия регистра.
-- Для раскладки оставляем запуск при отпускании: в приложениях с wtype
-- удержанный Shift может превратить Ctrl+C в Ctrl+Shift+C.
o.bind("SHIFT + PAUSE", "Сменить раскладку выделенного", "/home/proto/.local/bin/text-conv layout", { release = true })
o.bind("SHIFT + BREAK", "Сменить раскладку выделенного", "/home/proto/.local/bin/text-conv layout", { release = true })
-- Ctrl может менять символ Pause на Break. Сопоставляем физические коды
-- Pause и отдельной клавиши Break на нажатии, пока Ctrl ещё зажат.
-- Alt с wtype превращал Ctrl+V в Ctrl+Alt+V и запускал голосовой чат Hermes.
o.bind("CTRL + code:127", "Инвертировать регистр выделенного", "/home/proto/.local/bin/text-conv case")
o.bind("CTRL + code:419", "Инвертировать регистр выделенного", "/home/proto/.local/bin/text-conv case")
