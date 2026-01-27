# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Internal Tokens API' do
  let(:internal_token) { 'test-internal-token' }
  let!(:superapp) { Fabricate(:application, superapp: true) }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('INTERNAL_API_TOKEN', nil).and_return(internal_token)
  end

  describe 'POST /api/v1/internal/tokens' do
    let!(:account) { Fabricate(:account, username: 'tokenuser') }
    let!(:user) { Fabricate(:user, account: account, confirmed_at: Time.now.utc, approved: true) }

    context 'with valid internal token' do
      it 'generates a bearer token by account_id' do
        post '/api/v1/internal/tokens',
             params: { account_id: account.id },
             headers: { 'X-Internal-Token' => internal_token }

        expect(response).to have_http_status(201)
        json = response.parsed_body
        expect(json['access_token']).to be_present
        expect(json['token_type']).to eq('Bearer')
        expect(json['scope']).to eq('read write follow')
        expect(json['account_id']).to eq(account.id.to_s)
      end

      it 'generates a bearer token by email' do
        post '/api/v1/internal/tokens',
             params: { email: user.email },
             headers: { 'X-Internal-Token' => internal_token }

        expect(response).to have_http_status(201)
        json = response.parsed_body
        expect(json['access_token']).to be_present
      end

      it 'generates a token with custom scopes' do
        post '/api/v1/internal/tokens',
             params: { account_id: account.id, scopes: 'read' },
             headers: { 'X-Internal-Token' => internal_token }

        expect(response).to have_http_status(201)
        json = response.parsed_body
        expect(json['scope']).to eq('read')
      end

      it 'generates a token with custom expiration' do
        post '/api/v1/internal/tokens',
             params: { account_id: account.id, expires_in: 3600 },
             headers: { 'X-Internal-Token' => internal_token }

        expect(response).to have_http_status(201)
        json = response.parsed_body
        expect(json['expires_in']).to eq(3600)
      end

      it 'returns 404 for non-existent account' do
        post '/api/v1/internal/tokens',
             params: { account_id: 999_999 },
             headers: { 'X-Internal-Token' => internal_token }

        expect(response).to have_http_status(404)
      end

      it 'returns 404 for non-existent email' do
        post '/api/v1/internal/tokens',
             params: { email: 'nonexistent@example.com' },
             headers: { 'X-Internal-Token' => internal_token }

        expect(response).to have_http_status(404)
      end

      it 'returns 403 for non-functional user' do
        user.update!(disabled: true)

        post '/api/v1/internal/tokens',
             params: { account_id: account.id },
             headers: { 'X-Internal-Token' => internal_token }

        expect(response).to have_http_status(403)
      end

      it 'returns 403 for unconfirmed user' do
        user.update!(confirmed_at: nil)

        post '/api/v1/internal/tokens',
             params: { account_id: account.id },
             headers: { 'X-Internal-Token' => internal_token }

        expect(response).to have_http_status(403)
      end

      it 'returns 403 for unapproved user' do
        user.update!(approved: false)

        post '/api/v1/internal/tokens',
             params: { account_id: account.id },
             headers: { 'X-Internal-Token' => internal_token }

        expect(response).to have_http_status(403)
      end
    end

    context 'with invalid internal token' do
      it 'returns 401' do
        post '/api/v1/internal/tokens',
             params: { account_id: account.id },
             headers: { 'X-Internal-Token' => 'wrong-token' }

        expect(response).to have_http_status(401)
      end
    end

    context 'without internal token' do
      it 'returns 401' do
        post '/api/v1/internal/tokens',
             params: { account_id: account.id }

        expect(response).to have_http_status(401)
      end
    end
  end
end
