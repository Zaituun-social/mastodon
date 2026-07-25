# frozen_string_literal: true

class Api::V1::InterestsController < Api::BaseController
  before_action -> { authorize_if_got_token! :read }, only: :index
  before_action -> { doorkeeper_authorize! :read, :'read:accounts' }, only: :me
  before_action -> { doorkeeper_authorize! :write, :'write:accounts' }, only: :update_me
  before_action :require_user!, only: [:me, :update_me]

  # The interest taxonomy is curated and small (tens of entries), so the full
  # list is returned unpaginated. Recency ordering is also incompatible with
  # to_a_paginated_by_id, which cursors on the record's own id.
  def index
    cache_if_unauthenticated!
    render_interests(Interest.all)
  end

  def me
    render_interests(current_account.interests)
  end

  # Replace-set: the client sends the final desired state. An empty array clears
  # every interest. Unknown names change nothing and return 422, because
  # interests are server-curated and the client fetches them from #index, so an
  # unknown name is always a client bug rather than user input.
  def update_me
    normalized = requested_names.index_with { |name| Interest.normalize(name) }
    found      = Interest.matching_name(normalized.values.uniq).index_by(&:name)
    unknown    = requested_names.reject { |name| found.key?(normalized[name]) }.uniq

    return render json: { error: 'Unknown interests', unknown: unknown }, status: 422 if unknown.any?

    replace_interests!(found.values.map(&:id))

    render_interests(current_account.interests.reload)
  end

  private

  def requested_names
    @requested_names ||= Array(params[:interests]).map(&:to_s).compact_blank.uniq
  end

  def replace_interests!(interest_ids)
    ApplicationRecord.transaction do
      current_account.account_interests.where.not(interest_id: interest_ids).delete_all

      existing = current_account.account_interests.pluck(:interest_id)
      rows     = (interest_ids - existing).map do |interest_id|
        { account_id: current_account.id, interest_id: interest_id, created_at: Time.now.utc, updated_at: Time.now.utc }
      end

      AccountInterest.insert_all(rows, unique_by: [:account_id, :interest_id]) if rows.any?
    end
  end

  def render_interests(scope)
    interests = scope.to_a
    presenter = InterestsPresenter.new(interests)

    render json: sort_by_recency(interests, presenter), each_serializer: REST::InterestSerializer, presenter: presenter
  end

  # Most recently active first, name as the tiebreaker. Interests whose tags
  # have no statuses sort last.
  def sort_by_recency(interests, presenter)
    interests.sort_by { |interest| [-(presenter.last_status_ids[interest.id] || 0), interest.name] }
  end
end
