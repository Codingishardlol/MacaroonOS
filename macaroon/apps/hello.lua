-- Macaroon OS - sample app: Hello
return {
  title = "Hello",
  width = 28,
  height = 8,

  draw = function(win)
    win.setBackgroundColor(colours.white)
    win.setTextColor(colours.black)
    win.clear()
    win.setCursorPos(2, 2)
    win.write("Hi from Macaroon OS!")
    win.setCursorPos(2, 4)
    win.setTextColor(colours.grey)
    win.write("Click below:")
    -- Button
    win.setCursorPos(2, 5)
    win.setBackgroundColor(colours.blue)
    win.setTextColor(colours.white)
    win.write(" [ Press me ] ")
    win.setBackgroundColor(colours.white)
  end,

  onEvent = function(win, event, p1, cx, cy)
    if event == "mouse_click" and cx and cy then
      -- Button is row 5, cols 2..15
      if cy == 5 and cx >= 2 and cx <= 15 then
        win.setCursorPos(2, 6)
        win.setBackgroundColor(colours.white)
        win.setTextColor(colours.green)
        win.write("Pressed! @" .. tostring(os.time()))
        return false -- already drew directly, no full redraw needed
      end
    end
    return false
  end
}
