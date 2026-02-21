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
      # TODO: Start to implement here
      key = cache_key
      cached_value = Rails.cache.read(key)
      if cached_value
        @result = cached_value
        return
      end
      printf(key)
      rate = RateApiClient.get_rate(period: @period, hotel: @hotel, room: @room)
      if rate.success?
        parsed_rate = JSON.parse(rate.body)
        value = parsed_rate['rates'].detect { |r| r['period'] == @period && r['hotel'] == @hotel && r['room'] == @room }&.dig('rate')
        @result = value
        Rails.cache.write(key, value, expires_in: 5.minutes)
      else
        errors << rate.body['error']
      end
    end
  end
end
