# frozen_string_literal: true

class Api::V1::Timelines::TagsController < Api::V1::Timelines::BaseController
  # Tags are supplied in the request body (POST), so no pagination Link header
  # is emitted: clients paginate with max_id/since_id/min_id in the body.
  skip_after_action :insert_pagination_headers

  before_action -> { authorize_if_got_token! :read, :'read:statuses' }

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

    raise Mastodon::ValidationError, "Too many tags (maximum is #{MAX_TAGS})" if tag_names.size > MAX_TAGS

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
end
