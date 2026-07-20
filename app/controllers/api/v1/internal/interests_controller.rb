# frozen_string_literal: true

class Api::V1::Internal::InterestsController < Api::V1::Internal::BaseController
  MAX_BULK_ASSIGNMENTS = 1_000
  MAX_TAGS_IN_RESPONSE = 5_000

  def create
    return render_invalid_name(:interest, params[:interest]) unless valid_name?(params[:interest])
    return render_invalid_name(:tag, params[:tag]) unless valid_name?(params[:tag])

    interest_name = normalize(params[:interest])
    tag_name      = normalize(params[:tag])

    interest, interest_created = find_or_create_interest(interest_name)
    tag, tag_created           = find_or_create_tag(tag_name)

    return render_invalid_name(:tag, params[:tag]) if tag.nil?

    assignment_created = create_assignment(interest, tag)

    log_internal_action(:assign_tag_to_interest, interest)

    render json: {
      interest: interest.name,
      interest_id: interest.id.to_s,
      tag: tag.name,
      tag_id: tag.id.to_s,
      interest_created: interest_created,
      tag_created: tag_created,
      assignment_created: assignment_created,
    }, status: assignment_created ? 201 : 200
  end

  def destroy
    return render_invalid_name(:interest, params[:interest]) unless valid_name?(params[:interest])
    return render_invalid_name(:tag, params[:tag]) unless valid_name?(params[:tag])

    interest_name = normalize(params[:interest])
    tag_name      = normalize(params[:tag])

    interest = Interest.find_normalized(interest_name)
    tag      = Tag.find_normalized(tag_name)
    deleted  = false

    if interest.present? && tag.present?
      deleted = InterestTag.where(interest_id: interest.id, tag_id: tag.id).delete_all.positive?
      log_internal_action(:unassign_tag_from_interest, interest) if deleted
    end

    render json: { interest: interest_name, tag: tag_name, deleted: deleted }, status: 200
  end

  def bulk
    assignments = params[:assignments]

    return render json: { error: 'assignments must be an array' }, status: 422 unless assignments.is_a?(Array)
    return render json: { error: "Too many assignments (maximum is #{MAX_BULK_ASSIGNMENTS})" }, status: 422 if assignments.size > MAX_BULK_ASSIGNMENTS

    result = Internal::AssignTagsToInterestsService.new.call(assignments)

    Rails.logger.info("[Internal API] Action: bulk_assign_tags_to_interests, Count: #{result[:assignments_created]}, IP: #{request.remote_ip}")

    render json: result, status: 200
  end

  def tags
    interest = Interest.find_normalized(params[:name])

    return render json: { error: 'Interest not found' }, status: 404 if interest.nil?

    tags_count = interest.interest_tags.count

    if tags_count > MAX_TAGS_IN_RESPONSE
      return render json: {
        error: "Interest has too many tags for an unpaginated response (maximum is #{MAX_TAGS_IN_RESPONSE}), use GET /api/v1/interests/:name/tags",
        tags_count: tags_count,
      }, status: 422
    end

    render json: {
      interest: interest.name,
      interest_id: interest.id.to_s,
      tags_count: tags_count,
      tags: interest.tags.pluck(:name),
    }, status: 200
  end

  private

  def normalize(value)
    Interest.normalize(value.to_s)
  end

  # Validates the RAW input, not the normalized form: HashtagNormalizer strips
  # invalid characters, so "not a tag!" would normalize to a perfectly valid
  # "notatag" and nothing would ever be rejected. Same approach as
  # Api::V1::TagsController#set_or_create_tag.
  #
  # This has to happen before any create because Tag.find_or_create_by_names
  # uses `create`, not `create!`: an invalid name silently returns an unpersisted
  # record whose nil id would then violate interest_tags.tag_id NOT NULL.
  def valid_name?(raw_name)
    raw_name.present? && Tag::HASHTAG_NAME_RE.match?(raw_name.to_s)
  end

  def render_invalid_name(kind, value)
    render json: { error: "Invalid #{kind} name" }.merge(kind => value), status: 422
  end

  def find_or_create_interest(name)
    interest = Interest.find_normalized(name)
    return [interest, false] if interest.present?

    [Interest.create!(name: name), true]
  rescue ActiveRecord::RecordNotUnique
    [Interest.find_normalized(name), false]
  end

  def find_or_create_tag(name)
    tag = Tag.find_normalized(name)
    return [tag, false] if tag.present?

    tag = Tag.find_or_create_by_names(name).first
    tag&.persisted? ? [tag, true] : [nil, false]
  end

  def create_assignment(interest, tag)
    InterestTag.create!(interest: interest, tag: tag)
    true
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    false
  end
end
