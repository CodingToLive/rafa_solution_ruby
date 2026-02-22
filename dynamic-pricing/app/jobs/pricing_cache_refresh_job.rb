class PricingCacheRefreshJob < ApplicationJob
  include PricingConstants

  queue_as :default

  TTL = 5.minutes

  def perform
    start_time = Time.current
    Rails.logger.info("[PricingCacheRefreshJob] START at #{start_time}")

    # 1 upstream batch call
    current_quota = ::PricingUpstreamBudget.consume!(amount: 1)
    Rails.logger.info("[PricingCacheRefreshJob] Consumed quota. Current usage today: #{current_quota}")

    response = RateApiClient.get_all_rates

    unless response.success?
      Rails.logger.warn("[PricingCacheRefreshJob] Upstream error: #{safe_error(response)}")
      return
    end

    parsed = response.parsed_response
    rates  = parsed.is_a?(Hash) ? parsed["rates"] : nil

    unless rates.is_a?(Array)
      Rails.logger.warn("[PricingCacheRefreshJob] Invalid payload format")
      return
    end

    written = 0

    rates.each do |r|
      next unless r.is_a?(Hash)
      next unless r.key?("rate")

      key = "pricing:rate:v1:period=#{r['period']}:hotel=#{r['hotel']}:room=#{r['room']}"
      Rails.cache.write(key, r["rate"].to_i, expires_in: TTL)
      written += 1
    end

    duration = ((Time.current - start_time) * 1000).round(1)

    Rails.logger.info(
      "[PricingCacheRefreshJob] SUCCESS - Cached #{written} rates in #{duration}ms"
    )

  rescue PricingUpstreamBudget::QuotaExceeded => e
    Rails.logger.warn("[PricingCacheRefreshJob] SKIPPED - Quota exceeded: #{e.message}")
  rescue => e
    Rails.logger.error("[PricingCacheRefreshJob] CRASH - #{e.class}: #{e.message}")
    raise
  end

  private

  def safe_error(resp)
    pr = resp.respond_to?(:parsed_response) ? resp.parsed_response : nil
    pr.is_a?(Hash) ? pr["error"].to_s : "unknown_error"
  end
end