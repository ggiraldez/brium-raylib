require "http/headers"
require "http/client"

class Brium
  def initialize
    @access_token = File.read("#{ENV["HOME"]}/.config/brium/.access_token").strip
  end

  def send_message(message)
    headers = HTTP::Headers{"Authorization" => "Bearer #{@access_token}"}

    HTTP::Client.post "https://brium.me/api/messages", headers, body: message do |response|
      if response.status.ok?
        response.body_io.gets_to_end
      else
        "Error: #{response.status_message}"
      end
    end
  end
end
