# frozen_string_literal: true

class Api::V1::Timelines::InterestController < Api::V1::Timelines::BaseController
  before_action -> { authorize_if_got_token! :read, :'read:statuses' }
  before_action :load_interest

  PERMITTED_PARAMS = %i(local limit only_media remote).freeze

  # Unlike the multi-tag timeline this can stay a GET: only one short interest
  # name goes into the URL, so the pagination Link header stays small and
  # standard next/prev links keep working.
  def show
    cache_if_unauthenticated!
    @statuses = load_statuses
    render json: @statuses, each_serializer: REST::StatusSerializer, relationships: StatusRelationshipsPresenter.new(@statuses, current_user&.account_id)
  end

  private

  def require_auth?
    !Setting.timeline_preview
  end

  def load_interest
    @interest = Interest.find_normalized(params[:id]) || not_found
  end

  def load_statuses
    return [] if tag_ids.empty?

    preload_collection(interest_timeline_statuses, Status)
  end

  # No tag-count cap here. Api::V1::Timelines::TagsController::MAX_TAGS bounds
  # untrusted client input; an interest is a server-curated set and is trusted.
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
    @tag_ids ||= @interest.tag_ids
  end

  def next_path
    api_v1_timelines_interest_url params[:id], next_path_params
  end

  def prev_path
    api_v1_timelines_interest_url params[:id], prev_path_params
  end
end
