Rails.application.config.after_initialize do
  next unless Rails.env.development? || Rails.env.production?

  Thread.new do
    loop do
      PricingCacheRefreshJob.perform_later
      sleep 5.minutes
    rescue => e
      AppLog.error(source: "PricingRefresh", event: "thread_error", error_class: e.class.name, error: e.message)
      sleep 10.seconds
    end
  end
end