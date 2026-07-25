# frozen_string_literal: true

# Batch-loads the derived attributes of a set of interests in a constant number
# of queries, so serializing N interests never becomes N+1.
class InterestsPresenter
  attr_reader :tags_counts, :last_status_ids

  # @param [Enumerable<Interest>] interests
  def initialize(interests)
    @interest_ids    = interests.map(&:id)
    @tags_counts     = load_tags_counts
    @last_status_ids = load_last_status_ids
  end

  def tags_count(interest_id)
    @tags_counts[interest_id] || 0
  end

  # @return [Time, nil]
  def last_status_at(interest_id)
    status_id = @last_status_ids[interest_id]

    status_id && Mastodon::Snowflake.to_time(status_id)
  end

  private

  def load_tags_counts
    return {} if @interest_ids.empty?

    InterestTag.where(interest_id: @interest_ids).group(:interest_id).count
  end

  # Recency is derived from MAX(statuses_tags.status_id): Mastodon ids are
  # Snowflake, so the largest id is the most recent status.
  #
  # tags.last_status_at is unusable for this - it is only written for remote
  # statuses (app/lib/activitypub/activity/create.rb) and throttled to once per
  # 12 hours, so locally authored posts never update it.
  #
  # The lateral is what keeps this cheap: statuses_tags has primary key
  # (tag_id, status_id), so each interest_tags row costs one backwards index
  # seek with LIMIT 1. Cost is bounded by the size of the taxonomy rather than
  # by the number of statuses, and the statuses table is never touched.
  def load_last_status_ids
    return {} if @interest_ids.empty?

    binds = [
      ActiveRecord::Relation::QueryAttribute.new('interest_ids', @interest_ids, ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Array.new(ActiveModel::Type::BigInteger.new)),
    ]

    ActiveRecord::Base.connection.select_all(<<~SQL.squish, 'interest_last_status_ids', binds).cast_values.to_h
      SELECT it.interest_id, MAX(l.status_id)
      FROM interest_tags it
      CROSS JOIN LATERAL (
        SELECT st.status_id
        FROM statuses_tags st
        WHERE st.tag_id = it.tag_id
        ORDER BY st.status_id DESC
        LIMIT 1
      ) l
      WHERE it.interest_id = ANY($1)
      GROUP BY it.interest_id
    SQL
  end
end
