# frozen_string_literal: true

class Api::V1::Internal::BaseController < Api::BaseController
  skip_before_action :require_authenticated_user!
  skip_before_action :require_not_suspended!

  before_action :authenticate_service_token!

  private

  def authenticate_service_token!
    provided_token = request.headers['X-Internal-Token']
    expected_token = ENV.fetch('INTERNAL_API_TOKEN', nil)

    if expected_token.blank?
      render json: { error: 'Internal API not configured' }, status: 503
      return
    end

    unless ActiveSupport::SecurityUtils.secure_compare(provided_token.to_s, expected_token)
      render json: { error: 'Invalid service token' }, status: 401
    end
  end

  def log_internal_action(action, target)
    Rails.logger.info("[Internal API] Action: #{action}, Target: #{target.class}##{target.id}, IP: #{request.remote_ip}")
  end
end
