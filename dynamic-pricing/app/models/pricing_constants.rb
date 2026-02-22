module PricingConstants
  VALID_PERIODS = %w[Summer Autumn Winter Spring].freeze
  VALID_HOTELS = %w[FloatingPointResort GitawayHotel RecursionRetreat].freeze
  VALID_ROOMS = %w[SingletonRoom BooleanTwin RestfulKing].freeze

  ALL_COMBINATIONS = VALID_PERIODS.product(VALID_HOTELS, VALID_ROOMS).map { |period, hotel, room|
    { period: period, hotel: hotel, room: room }
  }.freeze

  def self.cache_key(period:, hotel:, room:)
    "pricing:rate:v1:period=#{period}:hotel=#{hotel}:room=#{room}"
  end
end
