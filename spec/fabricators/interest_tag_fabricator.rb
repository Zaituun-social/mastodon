# frozen_string_literal: true

Fabricator(:interest_tag) do
  interest
  tag { Fabricate.build(:tag) }
end
