require "raylib-cr"
require "raylib-cr/raygui"
require "./brium"

Raylib.init_window(800, 450, "Brium")
Raylib.set_target_fps(60)

PADDING = 20
SCROLLBAR_SIZE = 20
TEXT_SIZE = 20
BORDER_WIDTH = 1
SCROLL_SPEED = 10

brium_input = Channel(String).new
brium_output = Channel(String).new
quit = Channel(Nil).new

spawn do    
  brium = Brium.new
  while message = brium_input.receive
    brium_output.send ">> #{message}\n\n"
    response = brium.send_message message
    brium_output.send "#{response}\n"
  end
end

spawn do
  brium_input.send "?"
  show_text = false
  buffer = ""
  lines = 0
  scroll = Raylib::Vector2.new
  input_buffer = Array(UInt8).new(256, 0)

  until Raylib.close_window?
    sleep 1.milliseconds
    select
    when data = brium_output.receive
      buffer = buffer + data
      lines = buffer.lines.size
      scroll.y = -lines * TEXT_SIZE
    else
    end
    
    Raylib.begin_drawing
    Raylib.clear_background(Raylib::RAYWHITE)

    Raygui.set_style(Raygui::Control::Default, Raygui::DefaultProperty::TextSize, TEXT_SIZE)
    Raygui.set_style(Raygui::Control::ListView, Raygui::ListViewProperty::ScrollBarWidth, SCROLLBAR_SIZE)

    input_height = 32
    input_top = Raylib.get_screen_height - input_height - PADDING
    inner_width = Raylib.get_screen_width - 2 * PADDING

    if Raylib.key_pressed?(Raylib::KeyboardKey::Enter)
      input_message = String.new(input_buffer.to_unsafe, input_buffer.size).strip
      if !input_message.blank?
        brium_input.send input_message
      end
      input_buffer.fill(0)
    end

    if Raylib.key_down?(Raylib::KeyboardKey::Up)
      scroll.y += SCROLL_SPEED
    end
    if Raylib.key_down?(Raylib::KeyboardKey::Down)
      scroll.y -= SCROLL_SPEED
    end
    
    text_bounds = Raylib::Rectangle.new(
      x: PADDING,
      y: input_top,
      width: inner_width,
      height: input_height
    )
    Raygui.text_box(
      text_bounds,
      input_buffer.to_unsafe,
      input_buffer.size,
      true
    )

    bounds = Raylib::Rectangle.new(
      x: PADDING,
      y: PADDING,
      width: inner_width,
      height: input_top - 2 * PADDING
    )
    content_rec = Raylib::Rectangle.new(
      x: 0,
      y: 0,
      width: inner_width - SCROLLBAR_SIZE - 2*BORDER_WIDTH,
      height: lines * TEXT_SIZE + PADDING,
    )
    Raygui.scroll_panel(bounds, nil, content_rec, pointerof(scroll), out view)

    Raylib.begin_scissor_mode(view.x, view.y, view.width, view.height)
    y = scroll.y + view.y + PADDING/2
    buffer.each_line do |line|
      Raylib.draw_text(line, PADDING * 1.5, y, 20, Raylib::BLACK)
      y += 20
    end
    Raylib.end_scissor_mode

    Raylib.end_drawing
    
    Fiber.yield
  end

  quit.send nil
end

quit.receive

Raylib.close_window
