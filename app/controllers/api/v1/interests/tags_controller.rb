# frozen_string_literal: true

class Api::V1::Interests::TagsController < Api::BaseController
  TAGS_LIMIT = 100

  before_action -> { authorize_if_got_token! :read }
  before_action :set_interest
  before_action :set_results

  after_action :insert_pagination_headers

  # Paginates on interest_tags.id (insertion order) rather than tag id, so the
  # standard id-cursor helper applies unchanged. Cursor ids are opaque to
  # clients, which is already the contract for Mastodon pagination.
  def index
    cache_if_unauthenticated!
    render json: @results.map(&:tag), each_serializer: REST::TagSerializer, relationships: TagRelationshipsPresenter.new(@results.map(&:tag), current_user&.account_id)
  end

  private

  def set_interest
    @interest = Interest.find_normalized(params[:name]) || not_found
  end

  def set_results
    @results = InterestTag.where(interest_id: @interest.id).joins(:tag).eager_load(:tag).to_a_paginated_by_id(
      limit_param(TAGS_LIMIT),
      params_slice(:max_id, :since_id, :min_id)
    )
  end

  def next_path
    api_v1_interest_tags_url params[:name], pagination_params(max_id: pagination_max_id) if records_continue?
  end

  def prev_path
    api_v1_interest_tags_url params[:name], pagination_params(since_id: pagination_since_id) unless @results.empty?
  end

  def pagination_collection
    @results
  end

  def records_continue?
    @results.size == limit_param(TAGS_LIMIT)
  end
end
