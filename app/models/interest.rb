# frozen_string_literal: true

# == Schema Information
#
# Table name: interests
#
#  id         :bigint(8)        not null, primary key
#  name       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#

class Interest < ApplicationRecord
  include Paginable

  has_many :interest_tags, inverse_of: :interest, dependent: :destroy
  has_many :tags, through: :interest_tags

  has_many :account_interests, inverse_of: :interest, dependent: :destroy
  has_many :accounts, through: :account_interests

  before_validation :normalize_name

  validates :name, presence: true, format: { with: Tag::HASHTAG_NAME_RE }
  validates :name, uniqueness: { case_sensitive: false }

  class << self
    def matching_name(name_or_names)
      names = Array(name_or_names).map { |name| arel_table.lower(normalize(name)) }

      if names.size == 1
        where(arel_table[:name].lower.eq(names.first))
      else
        where(arel_table[:name].lower.in(names))
      end
    end

    def find_normalized(name)
      matching_name(name).first
    end

    def find_normalized!(name)
      find_normalized(name) || raise(ActiveRecord::RecordNotFound)
    end

    # Interest names follow the same normalization rules as hashtags, so that
    # the classifier does not need to know about them and casing differences
    # cannot produce duplicate interests.
    def normalize(str)
      Tag.normalize(str)
    end
  end

  private

  def normalize_name
    self.name = self.class.normalize(name) if name.present?
  end
end
