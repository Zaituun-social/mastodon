# frozen_string_literal: true

class Internal::CreateAccountService < BaseService
  def call(username:, email:, confirmed: false, role_name: nil, approved: false)
    role_id = resolve_role_id(role_name)
    password = SecureRandom.hex(16)

    account = Account.new(username: username)

    user = User.new(
      email: email,
      password: password,
      agreement: true,
      role_id: role_id,
      confirmed_at: confirmed ? Time.now.utc : nil,
      bypass_invite_request_check: true
    )

    account.suspended_at = nil
    user.account = account

    ApplicationRecord.transaction do
      user.save!

      if confirmed
        user.confirmed_at = nil
        user.mark_email_as_confirmed!
      end

      user.approve! if approved
    end

    {
      account: account.reload,
      user: user.reload,
      password: password,
    }
  end

  private

  def resolve_role_id(role_name)
    return nil if role_name.blank?

    role = UserRole.find_by(name: role_name)
    raise Mastodon::NotPermittedError, "Cannot find user role: #{role_name}" if role.nil?

    role.id
  end
end
