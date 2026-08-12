# frozen_string_literal: true

class Api::V1::Internal::AccountsController < Api::V1::Internal::BaseController
  FOLLOWED_TAGS_LIMIT = 500
  ACTIVE_TAGS_LIMIT   = 20

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
    user = User.find_by!(email: params[:old_email])
    account = user.account

    raise ActiveRecord::RecordNotFound, 'No account associated with user' if account.nil?

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

  def interests
    account  = Account.find(params[:id])
    follows  = TagFollow.where(account_id: account.id).eager_load(:tag).to_a
    activity = AccountTagActivityPresenter.new(account)

    log_internal_action(:read_account_interests, account)
    render json: serialize_account_interests(account, follows, activity), status: 200
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

  def serialize_account_interests(account, follows, activity)
    interests = account.interests.to_a

    # Not InterestsPresenter: it eagerly runs a lateral query for instance-wide
    # interest recency, which this endpoint no longer reports, so all that is
    # needed from it is the taxonomy size it derives with this same count.
    tags_counts = InterestTag.where(interest_id: interests.map(&:id)).group(:interest_id).count

    # Truncation drops the least active tags, never an arbitrary slice: the list
    # is ranked by this account's own engagement first, so the cap only ever
    # discards tags they follow but do not post in.
    returned = sort_by_activity(follows, activity).take(FOLLOWED_TAGS_LIMIT)

    {
      account_id: account.id.to_s,
      username: account.username,
      interests: sort_interests_by_activity(interests, activity).map { |interest| serialize_interest(interest, tags_counts, activity) },
      interests_count: interests.size,
      followed_tags: returned.map { |follow| serialize_followed_tag(follow, activity) },
      followed_tags_count: follows.size,
      followed_tags_truncated: returned.size < follows.size,
      active_tags: serialize_active_tags(follows, activity),
    }
  end

  # Most-active-first, so the caller sees the tags this account both follows and
  # engages with at the top. Tags followed but never posted in sort last.
  def sort_by_activity(follows, activity)
    follows.sort_by do |follow|
      [-activity.statuses_count(follow.tag_id), -(activity.last_status_at(follow.tag_id)&.to_i || 0), follow.tag.name]
    end
  end

  # Deliberately not Api::V1::InterestsController#sort_by_recency, which ranks by
  # instance-wide recency. Here the caller is profiling one account, so an
  # interest they never post in must not outrank one they post in daily just
  # because someone else was active in it.
  def sort_interests_by_activity(interests, activity)
    interests.sort_by do |interest|
      [-activity.interest_statuses_count(interest.id), -(activity.interest_last_status_at(interest.id)&.to_i || 0), interest.name]
    end
  end

  # statuses_count/last_status_at are this account's own activity, consistent
  # with followed_tags and active_tags - every such field in this payload is
  # account-scoped. tags_count is the size of the curated taxonomy entry, which
  # is a property of the interest itself. Instance-wide interest recency is not
  # included; GET /api/v1/interests already serves it.
  def serialize_interest(interest, tags_counts, activity)
    {
      id: interest.id.to_s,
      name: interest.name,
      tags_count: tags_counts[interest.id] || 0,
      statuses_count: activity.interest_statuses_count(interest.id),
      last_status_at: activity.interest_last_status_at(interest.id)&.iso8601,
    }
  end

  def serialize_followed_tag(follow, activity)
    {
      id: follow.tag_id.to_s,
      name: follow.tag.name,
      followed_at: follow.created_at.iso8601,
      statuses_count: activity.statuses_count(follow.tag_id),
      last_status_at: activity.last_status_at(follow.tag_id)&.iso8601,
    }
  end

  # Tags the account actually posts in, whether or not it follows them. Names
  # already loaded via the tag follows are reused, so at most one extra query
  # runs for the remainder.
  def serialize_active_tags(follows, activity)
    tag_ids = activity.top_tag_ids(ACTIVE_TAGS_LIMIT)
    return [] if tag_ids.empty?

    followed_ids = follows.map(&:tag_id).to_set
    names        = follows.to_h { |follow| [follow.tag_id, follow.tag.name] }
    missing      = tag_ids - names.keys
    names.merge!(Tag.where(id: missing).pluck(:id, :name).to_h) if missing.any?

    tag_ids.filter_map do |tag_id|
      next if names[tag_id].nil?

      {
        id: tag_id.to_s,
        name: names[tag_id],
        statuses_count: activity.statuses_count(tag_id),
        last_status_at: activity.last_status_at(tag_id)&.iso8601,
        following: followed_ids.include?(tag_id),
      }
    end
  end
end
