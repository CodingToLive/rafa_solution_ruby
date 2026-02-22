Rails.application.config.after_initialize do
  next unless Rails.env.development? || Rails.env.production?

  Thread.new do
    loop do
      PricingCacheRefreshJob.perform_later
      sleep 5.minutes
    rescue => e
      Rails.logger.error("[PricingRefresh] Thread error: #{e.class}: #{e.message}")
      sleep 10.seconds
    end
  end
end