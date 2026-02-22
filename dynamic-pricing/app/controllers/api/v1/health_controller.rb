class Api::V1::HealthController < ApplicationController
  include PricingConstants

  def index
    cached_count = ALL_COMBINATIONS.count { |combo|
      key = PricingConstants.cache_key(period: combo[:period], hotel: combo[:hotel], room: combo[:room])
      Rails.cache.read(key).present?
    }

    quota_key = PricingUpstreamBudget.key_for_today
    calls_today = Rails.cache.read(quota_key) || 0

    render json: {
      status: "ok",
      cache: {
        total_combinations: ALL_COMBINATIONS.size,
        cached_entries: cached_count,
        coverage: "#{((cached_count.to_f / ALL_COMBINATIONS.size) * 100).round(1)}%"
      },
      upstream_budget: {
        calls_today: calls_today,
        limit: PricingUpstreamBudget::LIMIT
      }
    }
  end
end
