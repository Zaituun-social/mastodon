# frozen_string_literal: true

# == Schema Information
#
# Table name: interest_tags
#
#  id          :bigint(8)        not null, primary key
#  interest_id :bigint(8)        not null
#  tag_id      :bigint(8)        not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#

class InterestTag < ApplicationRecord
  include Paginable

  belongs_to :interest
  belongs_to :tag

  validates :tag_id, uniqueness: { scope: :interest_id }
end
