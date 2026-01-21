# frozen_string_literal: true

class Api::V1::Internal::TokensController < Api::V1::Internal::BaseController
  DEFAULT_SCOPES = 'read write follow'

  def create
    user = find_user

    raise ActiveRecord::RecordNotFound, 'User not found' if user.nil?
    raise Mastodon::NotPermittedError, 'User is not functional' unless user.functional?

    access_token = generate_token(user)

    log_internal_action(:generate_token, user.account)
    render json: serialize_token(access_token), status: 201
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: 404
  rescue Mastodon::NotPermittedError => e
    render json: { error: e.message }, status: 403
  end

  private

  def find_user
    if token_params[:account_id].present?
      Account.find(token_params[:account_id]).user
    elsif token_params[:email].present?
      User.find_by(email: token_params[:email])
    end
  end

  def generate_token(user)
    scopes = token_params[:scopes].presence || DEFAULT_SCOPES
    expires_in = token_params[:expires_in].present? ? token_params[:expires_in].to_i : Doorkeeper.configuration.access_token_expires_in

    application = Doorkeeper::Application.find_by(superapp: true)

    Doorkeeper::AccessToken.create!(
      application_id: application&.id,
      resource_owner_id: user.id,
      scopes: scopes,
      expires_in: expires_in,
      use_refresh_token: Doorkeeper.configuration.refresh_token_enabled?
    )
  end

  def token_params
    params.permit(:account_id, :email, :scopes, :expires_in)
  end

  def serialize_token(token)
    {
      access_token: token.token,
      token_type: 'Bearer',
      scope: token.scopes.to_s,
      created_at: token.created_at.to_i,
      expires_in: token.expires_in,
      account_id: Account.find_by(user_id: token.resource_owner_id)&.id&.to_s,
    }
  end
end
