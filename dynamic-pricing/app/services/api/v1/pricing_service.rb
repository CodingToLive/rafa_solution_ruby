module Api::V1
  class PricingService < BaseService
    def initialize(period:, hotel:, room:)
      @period = period
      @hotel = hotel
      @room = room
    end

    def cache_key
      "pricing:rate:v1:period=#{@period}:hotel=#{@hotel}:room=#{@room}"
    end

    def run
      key = cache_key
      cached_value = Rails.cache.read(key)
      if cached_value
        @result = cached_value
        return
      end
      response = RateApiClient.get_rate(period: @period, hotel: @hotel, room: @room)

      if !response.success?
        errors << (response.parsed_response['error'] rescue 'Pricing service returned an error')
        return
      end

      parsed = response.parsed_response
      rates = parsed['rates']

      if rates.blank?
        errors << 'Pricing service returned an incomplete response'
        return
      end

      rate_entry = rates.detect { |r|
        r['period'] == @period &&
        r['hotel'] == @hotel &&
        r['room'] == @room
      }

      if !rate_entry&.key?('rate')
        errors << 'Pricing service returned an incomplete response'
        return
      end

      value = rate_entry['rate'].to_i
      Rails.cache.write(key, value, expires_in: 5.minutes)
      @result = value
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      errors << "Pricing service timed out: #{e.message}"
    rescue StandardError => e
      errors << "Pricing service unavailable: #{e.message}"
    end
  end
end
