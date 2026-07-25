# frozen_string_literal: true

# Bulk-assigns tags to interests, creating either as needed.
#
# Deliberately NOT transactional: one malformed name must not roll back the rest
# of the batch. Invalid entries are reported per-index and everything else is
# committed.
class Internal::AssignTagsToInterestsService < BaseService
  # @param [Enumerable<Hash>] assignments Entries of { interest:, tag: }
  # @return [Hash]
  def call(assignments)
    @errors = []

    pairs = normalize_pairs(assignments)

    interests, interests_created = resolve_interests(pairs.map(&:first).uniq)
    tags, tags_created           = resolve_tags(pairs.map(&:last).uniq)

    {
      processed: assignments.size,
      assignments_created: insert_assignments(pairs, interests, tags),
      interests_created: interests_created,
      tags_created: tags_created,
      errors: @errors,
    }
  end

  private

  # @return [Array<Array(String, String)>] valid [interest_name, tag_name] pairs
  def normalize_pairs(assignments)
    assignments.filter_map.with_index do |assignment, index|
      # String responds to :[] too, so key? is the check that actually excludes scalars
      next add_error(index, {}, 'Assignment must be an object') unless assignment.respond_to?(:key?)

      next add_error(index, assignment, 'Invalid interest name') unless valid_name?(assignment[:interest])
      next add_error(index, assignment, 'Invalid tag name') unless valid_name?(assignment[:tag])

      [Interest.normalize(assignment[:interest].to_s), Interest.normalize(assignment[:tag].to_s)]
    end.uniq
  end

  # Validates the RAW input, not the normalized form: HashtagNormalizer strips
  # invalid characters, so "not a tag!" would normalize to a valid "notatag" and
  # nothing would ever be rejected.
  #
  # This has to happen before any create because Tag.find_or_create_by_names
  # uses `create`, not `create!`: an invalid name silently returns an unpersisted
  # record whose nil id would then violate interest_tags.tag_id NOT NULL.
  def valid_name?(raw_name)
    raw_name.present? && Tag::HASHTAG_NAME_RE.match?(raw_name.to_s)
  end

  def add_error(index, assignment, message)
    @errors << { index: index, interest: assignment[:interest], tag: assignment[:tag], error: message }
    nil
  end

  # @return [Array(Hash<String, Integer>, Integer)] name => id, and created count
  def resolve_interests(names)
    return [{}, 0] if names.empty?

    existing = Interest.matching_name(names).pluck(:name, :id).to_h
    missing  = names - existing.keys

    return [existing, 0] if missing.empty?

    # Interests are a curated taxonomy in the tens, so a per-row create is fine
    # here and avoids insert_all's poor handling of the lower(name) expression index.
    created = missing.filter_map do |name|
      Interest.create!(name: name)
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      nil
    end

    [Interest.matching_name(names).pluck(:name, :id).to_h, created.size]
  end

  # @return [Array(Hash<String, Integer>, Integer)] name => id, and created count
  def resolve_tags(names)
    return [{}, 0] if names.empty?

    existing = Tag.matching_name(names).pluck(:name, :id).to_h
    missing  = names - existing.keys

    return [existing, 0] if missing.empty?

    created = Tag.find_or_create_by_names(missing).select(&:persisted?)

    [existing.merge(created.to_h { |tag| [tag.name, tag.id] }), created.size]
  end

  def insert_assignments(pairs, interests, tags)
    rows = pairs.filter_map do |(interest_name, tag_name)|
      interest_id = interests[interest_name]
      tag_id      = tags[tag_name]

      next if interest_id.nil? || tag_id.nil?

      { interest_id: interest_id, tag_id: tag_id, created_at: Time.now.utc, updated_at: Time.now.utc }
    end

    return 0 if rows.empty?

    InterestTag.insert_all(rows, unique_by: [:interest_id, :tag_id], returning: [:id]).length
  end
end
