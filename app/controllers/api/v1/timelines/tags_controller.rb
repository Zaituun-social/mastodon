# frozen_string_literal: true

class Api::V1::Timelines::TagsController < Api::V1::Timelines::BaseController
  before_action -> { authorize_if_got_token! :read, :'read:statuses' }

  PERMITTED_PARAMS = %i(local limit only_media remote tags).freeze
  MAX_TAGS = 100

  def show
    cache_if_unauthenticated!
    @statuses = load_statuses
    render json: @statuses, each_serializer: REST::StatusSerializer, relationships: StatusRelationshipsPresenter.new(@statuses, current_user&.account_id)
  end

  private

  def require_auth?
    !Setting.timeline_preview
  end

  def load_statuses
    return [] if tag_names.empty?

    raise(Mastodon::ValidationError) if tag_names.size > MAX_TAGS

    preload_collection(tags_timeline_statuses, Status)
  end

  def tags_timeline_statuses
    tags_feed.get(
      limit_param(DEFAULT_STATUSES_LIMIT),
      params[:max_id],
      params[:since_id],
      params[:min_id]
    )
  end

  def tags_feed
    TagsFeed.new(
      tag_names,
      current_account,
      local: truthy_param?(:local),
      remote: truthy_param?(:remote),
      only_media: truthy_param?(:only_media)
    )
  end

  def tag_names
    @tag_names ||= Array(params[:tags]).map(&:to_s).compact_blank
  end

  def permitted_params
    params.permit(:local, :limit, :only_media, :remote, tags: [])
  end

  def next_path
    api_v1_timelines_tags_url next_path_params
  end

  def prev_path
    api_v1_timelines_tags_url prev_path_params
  end
end
