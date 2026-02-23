class RateApiClient
  include HTTParty
  include PricingConstants
  base_uri ENV.fetch('RATE_API_URL', 'http://localhost:8080')
  headers "Content-Type" => "application/json"
  headers 'token' => ENV.fetch('RATE_API_TOKEN', '04aa6f42aa03f220c2ae9a276cd68c62')

  def self.get_rate(period:, hotel:, room:)
    params = {
      attributes: [
        {
          period: period,
          hotel: hotel,
          room: room
        }
      ]
    }.to_json
    self.post("/pricing", body: params, timeout: 5)
  end

  def self.get_all_rates
    params = {
      attributes: ALL_COMBINATIONS
    }.to_json
    self.post("/pricing", body: params, timeout: 20)
  end
end
