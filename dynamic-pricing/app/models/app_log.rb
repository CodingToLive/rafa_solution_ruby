module AppLog
  def self.info(source:, event:, **extra)
    Rails.logger.info(format(source: source, event: event, **extra))
  end

  def self.warn(source:, event:, **extra)
    Rails.logger.warn(format(source: source, event: event, **extra))
  end

  def self.error(source:, event:, **extra)
    Rails.logger.error(format(source: source, event: event, **extra))
  end

  def self.format(source:, event:, **extra)
    { source: source, event: event, **extra }.to_json
  end
end