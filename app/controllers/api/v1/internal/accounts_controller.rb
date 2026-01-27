# frozen_string_literal: true

class Api::V1::Internal::AccountsController < Api::V1::Internal::BaseController
  def create
    result = Internal::CreateAccountService.new.call(
      username: account_params[:username],
      email: account_params[:email],
      confirmed: account_params[:confirmed],
      role_name: account_params[:role],
      approved: account_params[:approved]
    )

    log_internal_action(:create_account, result[:account])
    render json: serialize_account_with_password(result), status: 201
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: 422
  rescue Mastodon::NotPermittedError => e
    render json: { error: e.message }, status: 403
  end

  def update
    account = Account.find(params[:id])

    result = Internal::ModifyAccountService.new.call(
      account: account,
      role: modify_params[:role],
      remove_role: modify_params[:remove_role],
      email: modify_params[:email],
      confirm: modify_params[:confirm],
      enable: modify_params[:enable],
      disable: modify_params[:disable],
      approve: modify_params[:approve],
      reset_password: modify_params[:reset_password],
      disable_2fa: modify_params[:disable_2fa],
      display_name: modify_params[:display_name]
    )

    log_internal_action(:modify_account, account)
    render json: serialize_account_with_optional_password(result), status: 200
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: 404
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: 422
  rescue Mastodon::NotPermittedError => e
    render json: { error: e.message }, status: 403
  end

  def destroy
    user = User.find_by!(email: params[:email])
    account = user.account

    raise ActiveRecord::RecordNotFound, 'No account associated with user' if account.nil?

    DeleteAccountService.new.call(
      account,
      reserve_email: params[:reserve_email] == 'true',
      reserve_username: params[:reserve_username] == 'true'
    )

    log_internal_action(:delete_account, account)
    render json: { id: account.id.to_s, username: account.username, email: user.email, deleted: true }, status: 200
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: 404
  end

  def approve
    account = Account.find(params[:id])
    user = account.user

    raise ActiveRecord::RecordNotFound, 'No user associated with account' if user.nil?

    user.approve!

    log_internal_action(:approve_account, account)
    render json: serialize_account(account.reload), status: 200
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: 404
  end

  def approve_batch
    approved_ids = []

    if params[:all]
      User.pending.find_each do |user|
        user.approve!
        approved_ids << user.account_id.to_s
      end
    elsif params[:number].present?
      User.pending.order(created_at: :asc).limit(params[:number].to_i).each do |user|
        user.approve!
        approved_ids << user.account_id.to_s
      end
    elsif params[:account_ids].present?
      params[:account_ids].each do |account_id|
        account = Account.find(account_id)
        account.user&.approve!
        approved_ids << account_id.to_s
      end
    else
      render json: { error: 'Must provide all, number, or account_ids parameter' }, status: 422
      return
    end

    Rails.logger.info("[Internal API] Action: approve_batch, Count: #{approved_ids.size}, IP: #{request.remote_ip}")
    render json: { approved_count: approved_ids.size, approved_ids: approved_ids }, status: 200
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: 404
  end

  private

  def account_params
    params.permit(:username, :email, :confirmed, :role, :approved)
  end

  def modify_params
    params.permit(:role, :remove_role, :email, :confirm, :enable, :disable, :approve, :reset_password, :disable_2fa, :display_name)
  end

  def serialize_account(account)
    user = account.user
    {
      id: account.id.to_s,
      username: account.username,
      email: user&.email,
      confirmed: user&.confirmed?,
      approved: user&.approved?,
      disabled: user&.disabled?,
      role: user&.role ? { id: user.role.id.to_s, name: user.role.name } : nil,
      created_at: account.created_at.iso8601,
    }
  end

  def serialize_account_with_password(result)
    serialize_account(result[:account]).merge(password: result[:password])
  end

  def serialize_account_with_optional_password(result)
    response = serialize_account(result[:account])
    response[:new_password] = result[:new_password] if result[:new_password]
    response[:updated_at] = result[:account].updated_at.iso8601
    response
  end
end
