# frozen_string_literal: true

class TagsFeed < PublicFeed
  # @param [Enumerable<String>, nil] tag_names Ignored when :tag_ids is given
  # @param [Account] account
  # @param [Hash] options
  # @option [Enumerable<Integer>] :tag_ids Pre-resolved tag ids, skips the name lookup
  # @option [Boolean] :local
  # @option [Boolean] :remote
  # @option [Boolean] :only_media
  def initialize(tag_names, account, options = {})
    options    = options.dup
    @tag_names = Array(tag_names)
    @tag_ids   = options.delete(:tag_ids)&.to_a
    super(account, options)
  end

  # @param [Integer] limit
  # @param [Integer] max_id
  # @param [Integer] since_id
  # @param [Integer] min_id
  # @return [Array<Status>]
  def get(limit, max_id = nil, since_id = nil, min_id = nil)
    scope = public_scope

    scope.merge!(tagged_with_any_scope)
    scope.merge!(local_only_scope) if local_only?
    scope.merge!(remote_only_scope) if remote_only?
    scope.merge!(account_filters_scope) if account?
    scope.merge!(media_only_scope) if media_only?

    scope.to_a_paginated_by_id(limit, max_id: max_id, since_id: since_id, min_id: min_id)
  end

  private

  def tagged_with_any_scope
    Status.group(:id).tagged_with(tag_ids)
  end

  def tag_ids
    @tag_ids ||= (Tag.matching_name(@tag_names).pluck(:id) if @tag_names.present?)
  end
end
