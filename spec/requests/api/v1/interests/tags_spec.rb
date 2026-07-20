# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Interest tags' do
  let(:user)    { Fabricate(:user) }
  let(:token)   { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read') }
  let(:headers) { { 'Authorization' => "Bearer #{token.token}" } }

  let(:interest) { Fabricate(:interest, name: 'politics') }

  describe 'GET /api/v1/interests/:name/tags' do
    subject { get "/api/v1/interests/#{name}/tags", params: params, headers: headers }

    let(:name)   { 'politics' }
    let(:params) { {} }

    context 'when the interest has tags' do
      before do
        %w(election parliament vote).each do |tag_name|
          Fabricate(:interest_tag, interest: interest, tag: Fabricate(:tag, name: tag_name))
        end
      end

      it 'returns every tag', :aggregate_failures do
        subject

        expect(response).to have_http_status(200)
        expect(response.content_type).to start_with('application/json')
        expect(response.parsed_body.pluck(:name)).to match_array(%w(election parliament vote))
      end

      context 'with a limit' do
        let(:params) { { limit: 2 } }

        it 'paginates and sets a Link header', :aggregate_failures do
          subject

          expect(response.parsed_body.size).to eq(2)
          expect(response.headers['Link']).to be_present
        end
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
  end
end
