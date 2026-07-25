# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Interests' do
  let(:user)    { Fabricate(:user) }
  let(:scopes)  { 'read write' }
  let(:token)   { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: scopes) }
  let(:headers) { { 'Authorization' => "Bearer #{token.token}" } }

  let(:account)  { Fabricate(:account) }
  let(:politics) { Fabricate(:interest, name: 'politics') }
  let(:sports)   { Fabricate(:interest, name: 'sports') }
  let(:cooking)  { Fabricate(:interest, name: 'cooking') }

  # politics gets the most recent status, sports an older one, cooking none
  def seed_interests!
    old_status = PostStatusService.new.call(account, text: 'the #football match')
    new_status = PostStatusService.new.call(account, text: 'the #election result')

    Fabricate(:interest_tag, interest: sports, tag: new_status && Tag.find_normalized('football'))
    Fabricate(:interest_tag, interest: politics, tag: Tag.find_normalized('election'))
    cooking

    [old_status, new_status]
  end

  def count_queries
    count = 0

    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |_, _, _, _, payload|
      count += 1 unless %w(SCHEMA TRANSACTION).include?(payload[:name])
    end

    yield

    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  describe 'GET /api/v1/interests' do
    subject { get '/api/v1/interests', headers: headers }

    before { seed_interests! }

    it 'returns interests ordered by recency with tagless ones last', :aggregate_failures do
      subject

      expect(response).to have_http_status(200)
      expect(response.content_type).to start_with('application/json')
      expect(response.parsed_body.pluck('name')).to eq(%w(politics sports cooking))
      expect(response.parsed_body.pluck('tags_count')).to eq([1, 1, 0])
      expect(response.parsed_body.last['last_status_at']).to be_nil
      expect(response.parsed_body.first['last_status_at']).to be_present
    end

    # Guards the presenter: serializing N interests must not become N+1.
    it 'does not issue more queries as interests are added' do
      get '/api/v1/interests', headers: headers # warm settings/permission caches
      baseline = count_queries { get '/api/v1/interests', headers: headers }

      5.times { |i| Fabricate(:interest, name: "extra#{i}") }

      expect(count_queries { get '/api/v1/interests', headers: headers }).to eq(baseline)
    end
  end

  describe 'GET /api/v1/interests/me' do
    subject { get '/api/v1/interests/me', headers: headers }

    before { Fabricate(:account_interest, account: user.account, interest: politics) }

    it 'returns only the account interests', :aggregate_failures do
      sports

      subject

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck('name')).to eq(['politics'])
    end

    context 'without an authentication token' do
      let(:headers) { {} }

      it 'returns http unauthorized' do
        subject

        expect(response).to have_http_status(401)
      end
    end
  end

  describe 'PUT /api/v1/interests/me' do
    subject { put '/api/v1/interests/me', params: params, headers: headers }

    let(:params) { { interests: %w(politics sports) } }

    before do
      politics
      sports
      cooking
    end

    it 'replaces the whole set', :aggregate_failures do
      Fabricate(:account_interest, account: user.account, interest: cooking)

      subject

      expect(response).to have_http_status(200)
      expect(user.account.interests.reload.pluck(:name)).to match_array(%w(politics sports))
    end

    it 'is idempotent' do
      subject

      expect { put '/api/v1/interests/me', params: params, headers: headers }
        .to_not(change { user.account.account_interests.reload.count })
    end

    context 'with an empty list' do
      let(:params) { { interests: [] } }

      it 'clears every interest' do
        Fabricate(:account_interest, account: user.account, interest: politics)

        subject

        expect(user.account.interests.reload).to be_empty
      end
    end

    context 'with a differently cased name' do
      let(:params) { { interests: %w(Politics) } }

      it 'resolves it' do
        subject

        expect(user.account.interests.reload.pluck(:name)).to eq(['politics'])
      end
    end

    context 'with an unknown interest' do
      let(:params) { { interests: %w(politics politcs) } }

      it 'changes nothing and returns 422', :aggregate_failures do
        Fabricate(:account_interest, account: user.account, interest: cooking)

        subject

        expect(response).to have_http_status(422)
        expect(response.parsed_body['unknown']).to eq(['politcs'])
        expect(user.account.interests.reload.pluck(:name)).to eq(['cooking'])
      end
    end

    context 'with the wrong scope' do
      let(:scopes) { 'read' }

      it 'returns http forbidden' do
        subject

        expect(response).to have_http_status(403)
      end
    end
  end
end
