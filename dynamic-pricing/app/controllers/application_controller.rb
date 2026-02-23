class ApplicationController < ActionController::API
  rescue_from StandardError, with: :internal_error

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

  private

  def internal_error(exception)
    AppLog.error(source: "ApplicationController", event: "unhandled_exception", error_class: exception.class.name, error: exception.message)
    render json: { error: "Internal server error" }, status: :internal_server_error
  end
end
