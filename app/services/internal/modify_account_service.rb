# frozen_string_literal: true

class Internal::ModifyAccountService < BaseService
  def call(account:, **options)
    user = account.user
    raise ActiveRecord::RecordNotFound, 'No user associated with account' if user.nil?

    result = { account: account, user: user }

    ApplicationRecord.transaction do
      apply_role_changes(user, options)
      apply_email_changes(user, options)
      apply_status_changes(user, options)
      apply_account_changes(account, options)

      if options[:reset_password]
        result[:new_password] = reset_password(user)
      end

      account.save!
      user.save!
    end

    result
  end

  private

  def apply_role_changes(user, options)
    if options[:role].present?
      role = UserRole.find_by(name: options[:role])
      raise Mastodon::NotPermittedError, "Cannot find role: #{options[:role]}" if role.nil?

      user.role_id = role.id
    elsif options[:remove_role]
      user.role_id = nil
    end
  end

  def apply_email_changes(user, options)
    user.email = options[:email] if options[:email].present?
    user.confirm if options[:confirm]
  end

  def apply_status_changes(user, options)
    user.disabled = false if options[:enable]
    user.disabled = true if options[:disable]
    user.approved = true if options[:approve]
    user.disable_two_factor! if options[:disable_2fa]
  end

  def apply_account_changes(account, options)
    account.display_name = options[:display_name] if options[:display_name].present?
  end

  def reset_password(user)
    password = SecureRandom.hex(16)
    user.password = password
    password
  end
end
