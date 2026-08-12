# frozen_string_literal: true

# Batch-loads how much a single account actually posts in each hashtag - and,
# by rolling those tags up through the interest taxonomy, in each interest - so
# callers can rank both by that account's own engagement rather than by global
# popularity.
#
# Counts cover the account's most recent RECENT_STATUSES_WINDOW statuses, not
# its whole history: this is a recent-activity signal, and the window is what
# keeps both queries cheap for prolific accounts.
class AccountTagActivityPresenter
  RECENT_STATUSES_WINDOW = 100

  # @param [Account] account
  def initialize(account)
    @counts                   = {}
    @last_status_ids          = {}
    @interest_counts          = {}
    @interest_last_status_ids = {}

    load_tag_activity(account.id)
    load_interest_activity(account.id)
  end

  def statuses_count(tag_id)
    @counts[tag_id] || 0
  end

  # @return [Time, nil]
  def last_status_at(tag_id)
    status_id = @last_status_ids[tag_id]

    status_id && Mastodon::Snowflake.to_time(status_id)
  end

  # Tag ids the account posts in most, busiest first, recency as the tiebreaker.
  def top_tag_ids(limit)
    @counts.keys.sort_by { |tag_id| [-@counts[tag_id], -(@last_status_ids[tag_id] || 0)] }.take(limit)
  end

  def tag_ids
    @counts.keys
  end

  def interest_statuses_count(interest_id)
    @interest_counts[interest_id] || 0
  end

  # @return [Time, nil]
  def interest_last_status_at(interest_id)
    status_id = @interest_last_status_ids[interest_id]

    status_id && Mastodon::Snowflake.to_time(status_id)
  end

  private

  # Driving from the account's own statuses is what makes this safe: the CTE is
  # served by index_statuses_20190820 - (account_id, id DESC) partial on
  # deleted_at IS NULL - so it is a backwards index scan capped at the window,
  # and the join uses index_statuses_tags_on_status_id. Starting from tag_id
  # instead would scan every status of a popular tag.
  #
  # Recency comes from MAX(statuses_tags.status_id) rather than
  # tags.last_status_at for the reason documented in InterestsPresenter: that
  # column is only written for remote statuses and is throttled to once every
  # 12 hours, so locally authored posts never update it.
  def load_tag_activity(account_id)
    rows = select_over_recent_statuses(account_id, 'account_tag_activity', <<~SQL.squish)
      SELECT st.tag_id, COUNT(*), MAX(st.status_id)
      FROM recent r
      JOIN statuses_tags st ON st.status_id = r.id
      GROUP BY st.tag_id
    SQL

    rows.each do |tag_id, statuses_count, last_status_id|
      @counts[tag_id]          = statuses_count
      @last_status_ids[tag_id] = last_status_id
    end
  end

  # Rolls tag activity up through the taxonomy, so an interest reflects how much
  # this account posts about it rather than how busy the instance is.
  #
  # COUNT(DISTINCT r.id) rather than summing the per-tag counts in Ruby: one
  # status carrying two tags of the same interest is one status, not two.
  # interest_tags is the curated taxonomy (small), so the extra join is cheap.
  def load_interest_activity(account_id)
    rows = select_over_recent_statuses(account_id, 'account_interest_activity', <<~SQL.squish)
      SELECT it.interest_id, COUNT(DISTINCT r.id), MAX(r.id)
      FROM recent r
      JOIN statuses_tags st ON st.status_id = r.id
      JOIN interest_tags it ON it.tag_id = st.tag_id
      GROUP BY it.interest_id
    SQL

    rows.each do |interest_id, statuses_count, last_status_id|
      @interest_counts[interest_id]          = statuses_count
      @interest_last_status_ids[interest_id] = last_status_id
    end
  end

  def select_over_recent_statuses(account_id, name, projection)
    binds = [
      ActiveRecord::Relation::QueryAttribute.new('account_id', account_id, ActiveModel::Type::BigInteger.new),
      ActiveRecord::Relation::QueryAttribute.new('window', RECENT_STATUSES_WINDOW, ActiveModel::Type::Integer.new),
    ]

    ActiveRecord::Base.connection.select_all(<<~SQL.squish, name, binds).cast_values
      WITH recent AS (
        SELECT id
        FROM statuses
        WHERE account_id = $1 AND deleted_at IS NULL
        ORDER BY id DESC
        LIMIT $2
      )
      #{projection}
    SQL
  end
end
