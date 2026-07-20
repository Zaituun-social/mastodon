# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TagsFeed do
  subject { described_class.new(tag_names, account, options) }

  let(:account)     { Fabricate(:account) }
  let(:options)     { {} }
  let(:tag_names)   { %w(life love) }

  let!(:life_status) { PostStatusService.new.call(account, text: 'my #life') }
  let!(:love_status) { PostStatusService.new.call(account, text: 'what is #love?') }

  before { PostStatusService.new.call(account, text: '#war never changes') }

  describe '#get' do
    it 'returns the union of the named tags, excluding others' do
      expect(subject.get(20).map(&:id)).to contain_exactly(life_status.id, love_status.id)
    end

    context 'with pre-resolved tag ids' do
      let(:tag_names) { nil }
      let(:options)   { { tag_ids: Tag.matching_name(%w(life love)).pluck(:id) } }

      it 'returns exactly what the name-based lookup returns' do
        expect(subject.get(20).map(&:id))
          .to eq(described_class.new(%w(life love), account).get(20).map(&:id))
      end

      it 'does not query tags by name' do
        feed          = subject # resolve the ids outside the measured block
        names_queried = false

        subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |_, _, _, _, payload|
          names_queried ||= payload[:sql].include?('FROM "tags"')
        end

        feed.get(20)

        expect(names_queried).to be(false)
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end
    end
  end
end
