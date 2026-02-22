class PricingCacheRefreshJob < ApplicationJob
  include PricingConstants

  queue_as :default
  retry_on StandardError, wait: 30.seconds, attempts: 3

  TTL = 5.minutes

  def perform
    start_time = Time.current
    AppLog.info(source: "PricingCacheRefreshJob", event: "start")

    ::PricingUpstreamBudget.check_quota!

    response = RateApiClient.get_all_rates

    unless response.success?
      AppLog.warn(source: "PricingCacheRefreshJob", event: "upstream_error", error: safe_error(response))
      return
    end

    current_quota = ::PricingUpstreamBudget.consume!(amount: 1)
    AppLog.info(source: "PricingCacheRefreshJob", event: "quota_consumed", usage_today: current_quota)

    parsed = response.parsed_response
    rates  = parsed.is_a?(Hash) ? parsed["rates"] : nil

    unless rates.is_a?(Array)
      AppLog.warn(source: "PricingCacheRefreshJob", event: "invalid_payload")
      return
    end

    written = 0

    rates.each do |r|
      next unless r.is_a?(Hash)
      next unless r.key?("rate")

      key = PricingConstants.cache_key(period: r['period'], hotel: r['hotel'], room: r['room'])
      Rails.cache.write(key, r["rate"].to_i, expires_in: TTL)
      written += 1
    end

    duration = ((Time.current - start_time) * 1000).round(1)

    AppLog.info(source: "PricingCacheRefreshJob", event: "success", cached_rates: written, duration_ms: duration)

  rescue PricingUpstreamBudget::QuotaExceeded => e
    AppLog.warn(source: "PricingCacheRefreshJob", event: "quota_exceeded", error: e.message)
  rescue => e
    AppLog.error(source: "PricingCacheRefreshJob", event: "crash", error_class: e.class.name, error: e.message)
    raise
  end

  private

  def safe_error(resp)
    pr = resp.respond_to?(:parsed_response) ? resp.parsed_response : nil
    pr.is_a?(Hash) ? pr["error"].to_s : "unknown_error"
  end
end