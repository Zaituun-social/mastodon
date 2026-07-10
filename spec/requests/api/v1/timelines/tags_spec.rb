# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Tags' do
  let(:user)    { Fabricate(:user) }
  let(:scopes)  { 'read:statuses' }
  let(:token)   { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: scopes) }
  let(:headers) { { 'Authorization' => "Bearer #{token.token}" } }

  describe 'GET /api/v1/timelines/tags' do
    subject do
      get '/api/v1/timelines/tags', headers: headers, params: params
    end

    shared_examples 'a successful request to the tags timeline' do
      it 'returns the expected statuses', :aggregate_failures do
        subject

        expect(response)
          .to have_http_status(200)
        expect(response.content_type)
          .to start_with('application/json')
        expect(response.parsed_body.pluck(:id))
          .to match_array(expected_statuses.map { |status| status.id.to_s })
          .and not_include(private_status.id)
      end
    end

    let(:account)         { Fabricate(:account) }
    let!(:private_status) { PostStatusService.new.call(account, visibility: :private, text: '#life could be a dream') }
    let!(:life_status)    { PostStatusService.new.call(account, text: 'tell me what is my #life without your #love') }
    let!(:war_status)     { PostStatusService.new.call(user.account, text: '#war, war never changes') }
    let!(:love_status)    { PostStatusService.new.call(account, text: 'what is #love?') }
    let!(:peace_status)   { PostStatusService.new.call(account, text: 'give #peace a chance') }
    let!(:hope_status)    { PostStatusService.new.call(account, text: 'a little #hope') }
    let!(:joy_status)     { PostStatusService.new.call(account, text: 'pure #joy') }
    let(:params)          { {} }

    it_behaves_like 'forbidden for wrong scope', 'profile'

    context 'when given a single tag' do
      let(:expected_statuses) { [life_status] }
      let(:params)            { { tags: %w(life) } }

      it_behaves_like 'a successful request to the tags timeline'
    end

    context 'when given multiple tags' do
      let(:expected_statuses) { [life_status, love_status, war_status] }
      let(:params)            { { tags: %w(life love war) } }

      it_behaves_like 'a successful request to the tags timeline'
    end

    context 'when given more than four tags' do
      let(:expected_statuses) { [life_status, love_status, war_status, peace_status, hope_status, joy_status] }
      let(:params)            { { tags: %w(life love war peace hope joy) } }

      it_behaves_like 'a successful request to the tags timeline'
    end

    context 'when no tags are given' do
      let(:params) { {} }

      it 'returns an empty array' do
        subject

        expect(response).to have_http_status(200)
        expect(response.parsed_body).to eq([])
      end
    end

    context 'with blank tag values' do
      let(:params) { { tags: ['', '  '] } }

      it 'returns an empty array' do
        subject

        expect(response).to have_http_status(200)
        expect(response.parsed_body).to eq([])
      end
    end

    context 'when given more than the maximum number of tags' do
      let(:params) { { tags: Array.new(101) { |i| "tag#{i}" } } }

      it 'returns http unprocessable entity' do
        subject

        expect(response).to have_http_status(422)
        expect(response.content_type)
          .to start_with('application/json')
      end
    end

    context 'with limit param' do
      let(:params) { { tags: %w(life love), limit: 1 } }

      it 'returns only the requested number of statuses' do
        subject

        expect(response.parsed_body.size).to eq(params[:limit])
      end

      it 'sets the correct pagination headers, preserving tags', :aggregate_failures do
        subject

        expect(response)
          .to include_pagination_headers(
            prev: api_v1_timelines_tags_url(limit: params[:limit], min_id: love_status.id, tags: %w(life love)),
            next: api_v1_timelines_tags_url(limit: params[:limit], max_id: love_status.id, tags: %w(life love))
          )
        expect(response.content_type)
          .to start_with('application/json')
      end
    end

    context 'when the instance allows public preview' do
      context 'when the user is not authenticated' do
        let(:headers)           { {} }
        let(:expected_statuses) { [life_status] }
        let(:params)            { { tags: %w(life) } }

        it_behaves_like 'a successful request to the tags timeline'
      end
    end

    context 'when the instance does not allow public preview' do
      before do
        Form::AdminSettings.new(timeline_preview: false).save
      end

      it_behaves_like 'forbidden for wrong scope', 'profile'

      context 'without an authentication token' do
        let(:headers) { {} }
        let(:params)  { { tags: %w(life) } }

        it 'returns http unprocessable entity' do
          subject

          expect(response).to have_http_status(422)
          expect(response.content_type)
            .to start_with('application/json')
        end
      end

      context 'when the user is authenticated' do
        let(:expected_statuses) { [life_status] }
        let(:params)            { { tags: %w(life) } }

        it_behaves_like 'a successful request to the tags timeline'
      end
    end
  end
end
