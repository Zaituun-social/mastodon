# frozen_string_literal: true

# Personal interest feed: the union timeline of every tag in every interest the
# authenticated account has selected. A live query, so a brand-new account gets a
# populated feed on the first request without any home-feed fan-out or backfill.
class Api::V1::Timelines::InterestsController < Api::V1::Timelines::BaseController
  before_action -> { doorkeeper_authorize! :read, :'read:statuses' }
  before_action :require_user!

  PERMITTED_PARAMS = %i(local limit only_media remote).freeze

  def show
    with_read_replica do
      @statuses      = load_statuses
      @relationships = StatusRelationshipsPresenter.new(@statuses, current_user&.account_id)
    end

    render json: @statuses, each_serializer: REST::StatusSerializer, relationships: @relationships
  end

  private

  def load_statuses
    return [] if tag_ids.empty?

    preload_collection(interest_timeline_statuses, Status)
  end

  def interest_timeline_statuses
    interest_feed.get(
      limit_param(DEFAULT_STATUSES_LIMIT),
      params[:max_id],
      params[:since_id],
      params[:min_id]
    )
  end

  def interest_feed
    TagsFeed.new(
      nil,
      current_account,
      tag_ids: tag_ids,
      local: truthy_param?(:local),
      remote: truthy_param?(:remote),
      only_media: truthy_param?(:only_media)
    )
  end

  def tag_ids
    @tag_ids ||= InterestTag.where(interest_id: current_account.interest_ids).distinct.pluck(:tag_id)
  end

  def next_path
    api_v1_timelines_interests_url next_path_params
  end

  def prev_path
    api_v1_timelines_interests_url prev_path_params
  end
end
