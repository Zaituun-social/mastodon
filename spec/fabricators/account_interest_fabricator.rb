# frozen_string_literal: true

Fabricator(:account_interest) do
  account { Fabricate.build(:account) }
  interest
end
