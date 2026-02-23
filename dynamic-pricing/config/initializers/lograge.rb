Rails.application.configure do
  config.lograge.enabled = true
  config.lograge.formatter = Lograge::Formatters::Json.new
  config.lograge.custom_options = lambda do |event|
    {
      timestamp: Time.current.iso8601(3),
      request_id: event.payload[:request_id]
    }
  end
end