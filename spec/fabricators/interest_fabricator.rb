# frozen_string_literal: true

Fabricator(:interest) do
  name { sequence(:interest) { |i| "#{Faker::Lorem.word}#{i}" } }
end
