# frozen_string_literal: true

# == Schema Information
#
# Table name: account_interests
#
#  id          :bigint(8)        not null, primary key
#  account_id  :bigint(8)        not null
#  interest_id :bigint(8)        not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#

class AccountInterest < ApplicationRecord
  include Paginable

  belongs_to :account
  belongs_to :interest

  validates :interest_id, uniqueness: { scope: :account_id }

  scope :for_local_distribution, -> { joins(account: :user).merge(User.signed_in_recently) }
end
