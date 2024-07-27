require "raylib-cr"
require "raylib-cr/raygui"
require "./brium"

class TextRenderer
  getter font : Raylib::Font
  getter text_size : Float32
  getter text_spacing : Float32

  def initialize(@font, @text_size, @text_spacing)
  end

  def line_height
    @text_size
  end

  def layout_lines(lines, width)
    view_lines = [] of String
    # puts "Laying out #{lines.size} lines of text with width #{width}"
    lines.each do |line|
      end_index = line.size
      start_index = 0

      if end_index == 0
        view_lines << line
        next
      end

      while end_index > start_index
        index = end_index
        text_width = Raylib.measure_text_ex(@font, line[start_index..index], @text_size, @text_spacing).x
        while index > start_index && text_width > width
          # FIXME: do a biscection here, instead of a linear search
          index -= 1
          while index > start_index && line[index] != ' '
            index -= 1
          end

          text_width = Raylib.measure_text_ex(@font, line[start_index..index], @text_size, @text_spacing).x
        end
        if index == start_index
          puts "Width too narrow to layout remaining text"
          view_lines << line[start_index..]
          break
        end

        view_lines << line[start_index..index]
        start_index = index + 1
      end
    end

    view_lines
  end

  def draw_text(text, x, y, color)
    Raylib.draw_text_ex(@font, text, Raylib::Vector2.new(x: x, y: y), @text_size, @text_spacing, color)
  end

  def render_text_buffer(view_lines, x, y, color)
    view_lines.each do |line|
      if line.size == 0
        y += line_height
        next
      end

      draw_text(line, x, y, color)
      y += line_height
    end
  end
end

class App
  PADDING        = 20
  SCROLLBAR_SIZE = 20
  BORDER_WIDTH   =  1
  SCROLL_SPEED   = 10

  TEXT_SIZE    = 20_f32
  TEXT_SPACING =  0_f32
  TEXT_COLOR   = Raylib::Color.new r: 80, g: 80, b: 80, a: 255

  @brium_input = Channel(String).new
  @brium_output = Channel(String).new

  @buffer = ""
  @lines = [] of String
  @scroll = Raylib::Vector2.new
  @input_buffer = Array(UInt8).new(256, 0)
  @view = Raylib::Rectangle.new

  @text_renderer : TextRenderer?

  def text_renderer
    @text_renderer.not_nil!
  end

  def init_text_renderer
    font = Raylib.load_font_ex("/usr/share/fonts/truetype/ubuntu/Ubuntu-R.ttf", TEXT_SIZE, nil, 0)
    if font != Raylib.get_font_default
      Raygui.set_font(font)
      Raygui.set_style(Raygui::Control::Default, Raygui::DefaultProperty::TextSpacing, TEXT_SPACING)
    end

    @text_renderer = TextRenderer.new(font, TEXT_SIZE, TEXT_SPACING)
  end

  def start_brium_fiber
    spawn do
      brium = Brium.new
      while message = @brium_input.receive
        @brium_output.send ">> #{message}\n\n"
        response = brium.send_message message
        @brium_output.send "#{response}\n"
      end
    end
  end

  def handle_brium_input
    select
    when data = @brium_output.receive
      @buffer += data
      @lines = text_renderer.layout_lines(@buffer.lines, @view.width - PADDING)
      @scroll.y = -@lines.size * text_renderer.line_height
    else
    end
  end

  def handle_user_input
    if Raylib.key_pressed?(Raylib::KeyboardKey::Enter)
      input_message = String.new(@input_buffer.to_unsafe, @input_buffer.size).strip
      if !input_message.blank?
        @brium_input.send input_message
      end
      @input_buffer.fill(0)
    end

    if Raylib.key_down?(Raylib::KeyboardKey::Up)
      @scroll.y += SCROLL_SPEED
    end
    if Raylib.key_down?(Raylib::KeyboardKey::Down)
      @scroll.y -= SCROLL_SPEED
    end
  end

  def render_ui
    input_height = 32
    input_top = Raylib.get_screen_height - input_height - PADDING
    inner_width = Raylib.get_screen_width - 2 * PADDING

    text_bounds = Raylib::Rectangle.new(
      x: PADDING,
      y: input_top,
      width: inner_width,
      height: input_height
    )
    Raygui.text_box(
      text_bounds,
      @input_buffer.to_unsafe,
      @input_buffer.size,
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
      height: @lines.size * text_renderer.line_height + PADDING,
    )
    Raygui.scroll_panel(bounds, nil, content_rec, pointerof(@scroll), out view)
    @view = view

    Raylib.begin_scissor_mode(view.x, view.y, view.width, view.height)
    text_renderer.render_text_buffer(
      @lines,
      view.x + PADDING/2,
      @scroll.y + view.y + PADDING/2,
      TEXT_COLOR
    )
    Raylib.end_scissor_mode
  end

  def run
    Raylib.init_window(600, 450, "Brium")
    Raylib.set_target_fps(60)
    Raygui.set_style(Raygui::Control::Default, Raygui::DefaultProperty::TextSize, TEXT_SIZE)
    Raygui.set_style(Raygui::Control::ListView, Raygui::ListViewProperty::ScrollBarWidth, SCROLLBAR_SIZE)

    init_text_renderer

    start_brium_fiber

    @brium_input.send "?"

    until Raylib.close_window?
      Raylib.begin_drawing
      begin
        Raylib.clear_background(Raylib::RAYWHITE)
        render_ui
      end
      Raylib.end_drawing

      # Fiber.yield
      sleep 1.milliseconds

      handle_brium_input
      handle_user_input
    end

    Raylib.close_window
  end
end

App.new.run
