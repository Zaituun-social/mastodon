# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Interest timeline' do
  let(:user)    { Fabricate(:user) }
  let(:scopes)  { 'read:statuses' }
  let(:token)   { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: scopes) }
  let(:headers) { { 'Authorization' => "Bearer #{token.token}" } }

  describe 'GET /api/v1/timelines/interest/:name' do
    subject { get "/api/v1/timelines/interest/#{name}", params: params, headers: headers }

    let(:account)         { Fabricate(:account) }
    let!(:private_status) { PostStatusService.new.call(account, visibility: :private, text: '#life could be a dream') }
    let!(:life_status)    { PostStatusService.new.call(account, text: 'tell me what is my #life without your #love') }
    let!(:war_status)     { PostStatusService.new.call(user.account, text: '#war, war never changes') }
    let!(:love_status)    { PostStatusService.new.call(account, text: 'what is #love?') }
    let!(:peace_status)   { PostStatusService.new.call(account, text: 'give #peace a chance') }
    let!(:hope_status)    { PostStatusService.new.call(account, text: 'a little #hope') }
    let!(:joy_status)     { PostStatusService.new.call(account, text: 'pure #joy') }

    let(:interest) { Fabricate(:interest, name: 'feelings') }
    let(:name)     { 'feelings' }
    let(:params)   { {} }

    def assign(*tag_names)
      tag_names.each { |tag_name| Fabricate(:interest_tag, interest: interest, tag: Tag.find_normalized(tag_name)) }
    end

    it_behaves_like 'forbidden for wrong scope', 'profile'

    context 'when the interest has a single tag' do
      before { assign('life') }

      it 'returns the tagged statuses', :aggregate_failures do
        subject

        expect(response).to have_http_status(200)
        expect(response.content_type).to start_with('application/json')
        expect(response.parsed_body.pluck(:id))
          .to contain_exactly(life_status.id.to_s)
          .and not_include(private_status.id.to_s)
      end
    end

    # The key regression against TagFeed::LIMIT_PER_MODE, which silently caps at 4.
    context 'when the interest has more than four tags' do
      before { assign('life', 'love', 'war', 'peace', 'hope', 'joy') }

      it 'returns statuses for every tag' do
        subject

        expect(response.parsed_body.pluck(:id))
          .to match_array([life_status, love_status, war_status, peace_status, hope_status, joy_status].map { |status| status.id.to_s })
      end
    end

    context 'when the interest has no tags' do
      before { interest }

      it 'returns an empty array', :aggregate_failures do
        subject

        expect(response).to have_http_status(200)
        expect(response.parsed_body).to eq([])
      end
    end

    context 'when the interest does not exist' do
      let(:name) { 'nonexistent' }

      it 'returns http not found' do
        subject

        expect(response).to have_http_status(404)
      end
    end

    context 'with limit param' do
      let(:params) { { limit: 1 } }

      before { assign('life', 'love') }

      it 'returns one status and a Link header', :aggregate_failures do
        subject

        expect(response.parsed_body.size).to eq(1)
        expect(response.headers['Link']).to be_present
      end
    end

    context 'with max_id param' do
      let(:params) { { max_id: love_status.id } }

      before { assign('life', 'love') }

      it 'returns only statuses older than max_id', :aggregate_failures do
        subject

        ids = response.parsed_body.pluck(:id)
        expect(ids).to include(life_status.id.to_s)
        expect(ids).to_not include(love_status.id.to_s)
      end
    end

    context 'when the instance does not allow public preview' do
      before do
        assign('life')
        Form::AdminSettings.new(timeline_preview: false).save
      end

      context 'without an authentication token' do
        let(:headers) { {} }

        it 'returns http unprocessable entity' do
          subject

          expect(response).to have_http_status(422)
        end
      end

      context 'when the user is authenticated' do
        it 'returns the tagged statuses' do
          subject

          expect(response.parsed_body.pluck(:id)).to eq([life_status.id.to_s])
        end
      end
    end
  end
end
