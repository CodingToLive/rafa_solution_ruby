class ApplicationController < ActionController::API
  def append_info_to_payload(payload)
    super
    payload[:request_id] = request.uuid
  end

  def method_not_allowed
    render json: { error: "Method not allowed" }, status: :method_not_allowed
  end

  def not_found
    render json: { error: "Not found" }, status: :not_found
  end
end
