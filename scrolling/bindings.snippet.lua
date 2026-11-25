-- Scrolling: ширина активной колонки и направление ленты.
o.bind("SUPER + ALT + W", "Scrolling: ширина колонки 50% / 100%", hl.dsp.layout("colresize +conf"))
o.bind("SUPER + ALT + V", "Scrolling: направление ленты", function()
  local direction = hl.get_config("scrolling.direction")
  hl.config({ scrolling = { direction = direction == "right" and "down" or "right" } })
end)
