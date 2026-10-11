-- Macaroon OS - sample app: About
return {
  title = "About",
  width = 30,
  height = 9,

  draw = function(win)
    win.setBackgroundColor(colours.white)
    win.setTextColor(colours.black)
    win.clear()
    win.setCursorPos(2, 1)
    win.setTextColor(colours.blue)
    win.write("macaroon OS v1")
    win.setTextColor(colours.black)
    win.setCursorPos(2, 3)
    win.write("LevelOS-style demo")
    win.setCursorPos(2, 4)
    win.write("Advanced Computer only")
    win.setCursorPos(2, 6)
    win.setTextColor(colours.grey)
    local w = ({ win.getSize() })[1]
    win.write(string.rep("-", w - 2))
    win.setCursorPos(2, 7)
    win.setTextColor(colours.black)
    win.write("F1=start Delete=close")
  end,

  onEvent = function(win, event, ...)
    return false
  end
}
