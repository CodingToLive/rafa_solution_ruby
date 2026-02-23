require "test_helper"

class Api::V1::PricingControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.cache.clear
  end

  test "should get pricing with all parameters" do
    mock_parsed = {
      'rates' => [
        { 'period' => 'Summer', 'hotel' => 'FloatingPointResort', 'room' => 'SingletonRoom', 'rate' => '15000' }
      ]
    }

    mock_response = OpenStruct.new(success?: true, parsed_response: mock_parsed)

    RateApiClient.stub(:get_rate, mock_response) do
      get api_v1_pricing_url, params: {
        period: "Summer",
        hotel: "FloatingPointResort",
        room: "SingletonRoom"
      }

      assert_response :success
      assert_equal "application/json", @response.media_type

      json_response = JSON.parse(@response.body)
      assert_equal 15000, json_response["rate"]
    end
  end

  test "should return 502 when rate API fails" do
    mock_response = OpenStruct.new(success?: false, parsed_response: { 'error' => 'Rate not found' })

    RateApiClient.stub(:get_rate, mock_response) do
      get api_v1_pricing_url, params: {
        period: "Summer",
        hotel: "FloatingPointResort",
        room: "SingletonRoom"
      }

      assert_response :bad_gateway
      assert_equal "application/json", @response.media_type

      json_response = JSON.parse(@response.body)
      assert_includes json_response["error"], "Rate not found"
    end
  end

  test "should return error without any parameters" do
    get api_v1_pricing_url

    assert_response :bad_request
    assert_equal "application/json", @response.media_type

    json_response = JSON.parse(@response.body)
    assert_includes json_response["error"], "Missing required parameters"
  end

  test "should handle empty parameters" do
    get api_v1_pricing_url, params: {
      period: "",
      hotel: "",
      room: ""
    }

    assert_response :bad_request
    assert_equal "application/json", @response.media_type

    json_response = JSON.parse(@response.body)
    assert_includes json_response["error"], "Missing required parameters"
  end

  test "should reject invalid period" do
    get api_v1_pricing_url, params: {
      period: "summer-2024",
      hotel: "FloatingPointResort",
      room: "SingletonRoom"
    }

    assert_response :bad_request
    assert_equal "application/json", @response.media_type

    json_response = JSON.parse(@response.body)
    assert_includes json_response["error"], "Invalid period"
  end

  test "should reject invalid hotel" do
    get api_v1_pricing_url, params: {
      period: "Summer",
      hotel: "InvalidHotel",
      room: "SingletonRoom"
    }

    assert_response :bad_request
    assert_equal "application/json", @response.media_type

    json_response = JSON.parse(@response.body)
    assert_includes json_response["error"], "Invalid hotel"
  end

  test "should reject invalid room" do
    get api_v1_pricing_url, params: {
      period: "Summer",
      hotel: "FloatingPointResort",
      room: "InvalidRoom"
    }

    assert_response :bad_request
    assert_equal "application/json", @response.media_type

    json_response = JSON.parse(@response.body)
    assert_includes json_response["error"], "Invalid room"
  end

  test "should return 504 when API times out" do
    RateApiClient.stub(:get_rate, ->(*) { raise Net::ReadTimeout, "execution expired" }) do
      get api_v1_pricing_url, params: {
        period: "Summer",
        hotel: "FloatingPointResort",
        room: "SingletonRoom"
      }

      assert_response :gateway_timeout
      json_response = JSON.parse(@response.body)
      assert_includes json_response["error"], "timed out"
    end
  end

  test "should return 502 when rate field is missing" do
    mock_parsed = {
      'rates' => [
        { 'period' => 'Summer', 'hotel' => 'FloatingPointResort', 'room' => 'SingletonRoom' }
      ]
    }
    mock_response = OpenStruct.new(success?: true, parsed_response: mock_parsed)

    RateApiClient.stub(:get_rate, mock_response) do
      get api_v1_pricing_url, params: {
        period: "Summer",
        hotel: "FloatingPointResort",
        room: "SingletonRoom"
      }

      assert_response :bad_gateway
      json_response = JSON.parse(@response.body)
      assert_includes json_response["error"], "invalid rate"
    end
  end

  test "should return 502 when rates array is empty" do
    mock_parsed = { 'rates' => [] }
    mock_response = OpenStruct.new(success?: true, parsed_response: mock_parsed)

    RateApiClient.stub(:get_rate, mock_response) do
      get api_v1_pricing_url, params: {
        period: "Summer",
        hotel: "FloatingPointResort",
        room: "SingletonRoom"
      }

      assert_response :bad_gateway
      json_response = JSON.parse(@response.body)
      assert_includes json_response["error"], "no rates"
    end
  end

  test "cache hit does not call API" do
    key = PricingConstants.cache_key(period: "Summer", hotel: "FloatingPointResort", room: "SingletonRoom")
    Rails.cache.write(key, 15000, expires_in: 5.minutes)

    RateApiClient.stub(:get_rate, ->(*) { raise "API should not be called" }) do
      get api_v1_pricing_url, params: {
        period: "Summer",
        hotel: "FloatingPointResort",
        room: "SingletonRoom"
      }

      assert_response :success
      json_response = JSON.parse(@response.body)
      assert_equal 15000, json_response["rate"]
    end
  end

  test "should fetch cache response" do
    mock_parsed = {
      'rates' => [
        { 'period' => 'Summer', 'hotel' => 'FloatingPointResort', 'room' => 'SingletonRoom', 'rate' => '15000' }
      ]
    }

    mock_response = OpenStruct.new(success?: true, parsed_response: mock_parsed)

    RateApiClient.stub(:get_rate, mock_response) do
      get api_v1_pricing_url, params: {
        period: "Summer",
        hotel: "FloatingPointResort",
        room: "SingletonRoom"
      }

      assert_response :success
      assert_equal "application/json", @response.media_type

      json_response = JSON.parse(@response.body)
      assert_equal 15000, json_response["rate"]

      cache_value = Rails.cache.read("pricing:rate:v1:period=Summer:hotel=FloatingPointResort:room=SingletonRoom")
      assert_equal 15000, cache_value
    end
  end

  test "POST returns 405 method not allowed" do
    post api_v1_pricing_url

    assert_response :method_not_allowed
    json_response = JSON.parse(@response.body)
    assert_equal "Method not allowed", json_response["error"]
  end

  test "PUT returns 405 method not allowed" do
    put api_v1_pricing_url

    assert_response :method_not_allowed
    json_response = JSON.parse(@response.body)
    assert_equal "Method not allowed", json_response["error"]
  end

  test "DELETE returns 405 method not allowed" do
    delete api_v1_pricing_url

    assert_response :method_not_allowed
  end

  test "unknown route returns 404" do
    get "/api/v2/pricing"

    assert_response :not_found
    json_response = JSON.parse(@response.body)
    assert_equal "Not found", json_response["error"]
  end
end
