# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Personal interest timeline' do
  let(:user)    { Fabricate(:user) }
  let(:scopes)  { 'read:statuses' }
  let(:token)   { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: scopes) }
  let(:headers) { { 'Authorization' => "Bearer #{token.token}" } }

  describe 'GET /api/v1/timelines/interests' do
    subject { get '/api/v1/timelines/interests', params: params, headers: headers }

    let(:author)          { Fabricate(:account) }
    let!(:private_status) { PostStatusService.new.call(author, visibility: :private, text: '#life could be a dream') }
    let!(:life_status)    { PostStatusService.new.call(author, text: 'tell me what is my #life without your #love') }
    let!(:war_status)     { PostStatusService.new.call(author, text: '#war, war never changes') }
    let!(:love_status)    { PostStatusService.new.call(author, text: 'what is #love?') }
    let!(:peace_status)   { PostStatusService.new.call(author, text: 'give #peace a chance') }
    let!(:hope_status)    { PostStatusService.new.call(author, text: 'a little #hope') }
    let!(:joy_status)     { PostStatusService.new.call(author, text: 'pure #joy') }

    let(:feelings) { Fabricate(:interest, name: 'feelings') }
    let(:conflict) { Fabricate(:interest, name: 'conflict') }
    let(:params)   { {} }

    def assign(interest, *tag_names)
      tag_names.each { |tag_name| Fabricate(:interest_tag, interest: interest, tag: Tag.find_normalized(tag_name)) }
    end

    def select_interests(*interests)
      interests.each { |interest| Fabricate(:account_interest, account: user.account, interest: interest) }
    end

    it_behaves_like 'forbidden for wrong scope', 'profile'

    context 'when the account has interests' do
      before do
        assign(feelings, 'life', 'love', 'hope', 'joy', 'peace')
        assign(conflict, 'war')
        select_interests(feelings, conflict)
      end

      it 'returns the union across every selected interest, more than four tags honored', :aggregate_failures do
        subject

        expect(response).to have_http_status(200)
        expect(response.content_type).to start_with('application/json')
        expect(response.parsed_body.pluck(:id))
          .to match_array([life_status, love_status, hope_status, joy_status, peace_status, war_status].map { |status| status.id.to_s })
          .and not_include(private_status.id.to_s)
      end
    end

    context 'when a status matches tags from two different selected interests' do
      before do
        # #love is in feelings, and we also drop it into conflict so love_status is double-tagged
        assign(feelings, 'love')
        assign(conflict, 'love', 'war')
        select_interests(feelings, conflict)
      end

      it 'returns that status only once' do
        subject

        expect(response.parsed_body.pluck(:id).count(love_status.id.to_s)).to eq(1)
      end
    end

    context 'when the account has no interests' do
      it 'returns an empty array', :aggregate_failures do
        subject

        expect(response).to have_http_status(200)
        expect(response.parsed_body).to eq([])
      end
    end

    context 'when the account has an interest with no tags' do
      before { select_interests(feelings) }

      it 'returns an empty array' do
        subject

        expect(response.parsed_body).to eq([])
      end
    end

    context 'with limit param' do
      let(:params) { { limit: 1 } }

      before do
        assign(feelings, 'life', 'love')
        select_interests(feelings)
      end

      it 'returns one status and a Link header', :aggregate_failures do
        subject

        expect(response.parsed_body.size).to eq(1)
        expect(response.headers['Link']).to be_present
      end
    end

    context 'with max_id param' do
      let(:params) { { max_id: love_status.id } }

      before do
        assign(feelings, 'life', 'love')
        select_interests(feelings)
      end

      it 'returns only statuses older than max_id', :aggregate_failures do
        subject

        ids = response.parsed_body.pluck(:id)
        expect(ids).to include(life_status.id.to_s)
        expect(ids).to_not include(love_status.id.to_s)
      end
    end

    context 'when an author is blocked' do
      before do
        assign(feelings, 'life')
        select_interests(feelings)
        user.account.block!(author)
      end

      it 'excludes the blocked author statuses' do
        subject

        expect(response.parsed_body.pluck(:id)).to_not include(life_status.id.to_s)
      end
    end

    context 'without an authentication token' do
      let(:headers) { {} }

      it 'returns http unauthorized' do
        subject

        expect(response).to have_http_status(401)
      end
    end

    # Unlike the per-interest timeline, this feed is always personal and must
    # require a user even when the instance allows public preview.
    context 'when the instance allows public preview but there is no token' do
      let(:headers) { {} }

      before { Form::AdminSettings.new(timeline_preview: true).save }

      it 'still returns http unauthorized' do
        subject

        expect(response).to have_http_status(401)
      end
    end
  end
end
