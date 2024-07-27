require "raylib-cr"
require "raylib-cr/raygui"
require "./brium"

class TextView
  getter font : Raylib::Font
  getter text_size : Float32
  getter text_spacing : Float32

  getter text : String = ""
  getter width : Float32?

  @lines = [] of String

  def initialize(@font, @text_size, @text_spacing)
  end

  def set_text(@text)
  end

  def set_width(width : Float32)
    @width = width
  end

  def line_height
    @text_size
  end

  def compute_height
    @lines.size * line_height
  end

  def force_layout
    width = @width || 0_f32
    @lines.clear
    @text.lines.each do |line|
      end_index = line.size
      start_index = 0

      if end_index == 0
        @lines << line
        next
      end

      while end_index > start_index
        index = end_index
        text_width = Raylib.measure_text_ex(@font, line[start_index..index], @text_size, @text_spacing).x
        while index > start_index && text_width > width
          # FIXME: Instead of starting from the end, start from 0 and move
          # forward character by character using the GlyphInfo and atlas
          # rectangles from Raylib
          index -= 1
          while index > start_index && line[index] != ' '
            index -= 1
          end

          text_width = Raylib.measure_text_ex(@font, line[start_index..index], @text_size, @text_spacing).x
        end
        if index == start_index
          puts "Width too narrow to layout remaining text"
          @lines << line[start_index..]
          break
        end

        @lines << line[start_index..index]
        start_index = index + 1
      end
    end
  end

  def render(x, y, color)
    @lines.each do |line|
      if line.size == 0
        y += line_height
        next
      end

      Raylib.draw_text_ex(@font, line, Raylib::Vector2.new(x: x, y: y), @text_size, @text_spacing, color)
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
  @scroll = Raylib::Vector2.new
  @input_buffer = Array(UInt8).new(256, 0)
  @view = Raylib::Rectangle.new

  @text_view : TextView?

  def text_view
    @text_view.not_nil!
  end

  def init_text_view
    # FIXME: Load more codepoints for the fonts, otherwise only the standard
    # ASCII chars are supported
    font = Raylib.load_font_ex("/usr/share/fonts/truetype/ubuntu/Ubuntu-R.ttf", TEXT_SIZE, nil, 0)
    if font != Raylib.get_font_default
      Raygui.set_font(font)
      Raygui.set_style(Raygui::Control::Default, Raygui::DefaultProperty::TextSpacing, TEXT_SPACING)
    end

    @text_view = TextView.new(font, TEXT_SIZE, TEXT_SPACING)
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
      text_view.set_text(@buffer)
      text_view.set_width(@view.width - PADDING)
      text_view.force_layout()
      @scroll.y = -text_view.compute_height()
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
      height: text_view.compute_height(),
    )
    Raygui.scroll_panel(bounds, nil, content_rec, pointerof(@scroll), out view)
    @view = view

    Raylib.begin_scissor_mode(view.x, view.y, view.width, view.height)
    text_view.render(
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

    init_text_view

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
