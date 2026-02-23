module Api::V1
  class PricingService < BaseService
    def initialize(period:, hotel:, room:)
      @period = period
      @hotel = hotel
      @room = room
    end

    def run
      key = PricingConstants.cache_key(period: @period, hotel: @hotel, room: @room)
      cached_value = Rails.cache.read(key)
      if cached_value
        AppLog.info(source: "PricingService", event: "cache_hit", key: key)
        @result = cached_value
        return
      end

      AppLog.info(source: "PricingService", event: "cache_miss", key: key)

      begin
        PricingUpstreamBudget.check_quota!
      rescue PricingUpstreamBudget::QuotaExceeded => e
        @error_status = :service_unavailable
        errors << "Upstream API quota exhausted"
        return
      end

      response = RateApiClient.get_rate(period: @period, hotel: @hotel, room: @room)

      unless response.success?
        @error_status = :bad_gateway
        errors << (response.parsed_response['error'] rescue 'Pricing service returned an error')
        return
      end

      PricingUpstreamBudget.consume!(amount: 1)

      parsed = response.parsed_response
      rates = parsed['rates']

      if rates.blank?
        @error_status = :bad_gateway
        errors << 'Pricing service returned no rates'
        return
      end

      rate_entry = rates.detect { |r|
        r['period'] == @period &&
        r['hotel'] == @hotel &&
        r['room'] == @room
      }

      unless rate_entry
        @error_status = :bad_gateway
        errors << "Pricing service did not return the requested combination"
        return
      end

      raw_rate = rate_entry['rate']

      if !raw_rate.is_a?(Numeric) && !raw_rate.to_s.match?(/\A-?\d+(\.\d+)?\z/)
        @error_status = :bad_gateway
        errors << 'Pricing service returned an invalid rate'
        return
      end

      value = raw_rate.to_f
      Rails.cache.write(key, value, expires_in: 5.minutes)
      @result = value
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      @error_status = :gateway_timeout
      errors << "Pricing service timed out: #{e.message}"
    rescue StandardError => e
      @error_status = :service_unavailable
      errors << "Pricing service unavailable: #{e.message}"
    end
  end
end
