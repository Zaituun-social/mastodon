# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Internal Accounts API' do
  let(:internal_token) { 'test-internal-token' }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('INTERNAL_API_TOKEN', nil).and_return(internal_token)
  end

  describe 'POST /api/v1/internal/accounts' do
    let(:params) do
      {
        username: 'newuser',
        email: 'newuser@example.com',
        confirmed: true,
        approved: true,
      }
    end

    context 'with valid internal token' do
      it 'creates a new account' do
        post '/api/v1/internal/accounts',
             params: params,
             headers: { 'X-Internal-Token' => internal_token }

        expect(response).to have_http_status(201)
        json = response.parsed_body
        expect(json['username']).to eq('newuser')
        expect(json['email']).to eq('newuser@example.com')
        expect(json['confirmed']).to be true
        expect(json['approved']).to be true
        expect(json['password']).to be_present
      end

      it 'creates account with role' do
        role = Fabricate(:user_role, name: 'TestRole')

        post '/api/v1/internal/accounts',
             params: params.merge(role: 'TestRole'),
             headers: { 'X-Internal-Token' => internal_token }

        expect(response).to have_http_status(201)
        json = response.parsed_body
        expect(json['role']['name']).to eq('TestRole')
      end

      it 'returns error for invalid role' do
        post '/api/v1/internal/accounts',
             params: params.merge(role: 'NonExistentRole'),
             headers: { 'X-Internal-Token' => internal_token }

        expect(response).to have_http_status(403)
      end

      it 'returns validation error for duplicate username' do
        Fabricate(:account, username: 'newuser')

        post '/api/v1/internal/accounts',
             params: params,
             headers: { 'X-Internal-Token' => internal_token }

        expect(response).to have_http_status(422)
      end
    end

    context 'with invalid internal token' do
      it 'returns 401' do
        post '/api/v1/internal/accounts',
             params: params,
             headers: { 'X-Internal-Token' => 'wrong-token' }

        expect(response).to have_http_status(401)
      end
    end

    context 'without internal token' do
      it 'returns 401' do
        post '/api/v1/internal/accounts', params: params

        expect(response).to have_http_status(401)
      end
    end

    context 'when internal API is not configured' do
      before do
        allow(ENV).to receive(:fetch).with('INTERNAL_API_TOKEN', nil).and_return(nil)
      end

      it 'returns 503' do
        post '/api/v1/internal/accounts',
             params: params,
             headers: { 'X-Internal-Token' => 'any-token' }

        expect(response).to have_http_status(503)
      end
    end
  end

  describe 'PATCH /api/v1/internal/accounts/:id' do
    let!(:account) { Fabricate(:account, username: 'existinguser') }
    let!(:user) { Fabricate(:user, account: account, email: 'existing@example.com') }

    context 'with valid internal token' do
      it 'updates user email' do
        patch "/api/v1/internal/accounts/#{account.id}",
              params: { email: 'newemail@example.com' },
              headers: { 'X-Internal-Token' => internal_token }

        expect(response).to have_http_status(200)
        expect(user.reload.email).to eq('newemail@example.com')
      end

      it 'resets password and returns new password' do
        patch "/api/v1/internal/accounts/#{account.id}",
              params: { reset_password: true },
              headers: { 'X-Internal-Token' => internal_token }

        expect(response).to have_http_status(200)
        json = response.parsed_body
        expect(json['new_password']).to be_present
      end

      it 'enables disabled user' do
        user.update!(disabled: true)

        patch "/api/v1/internal/accounts/#{account.id}",
              params: { enable: true },
              headers: { 'X-Internal-Token' => internal_token }

        expect(response).to have_http_status(200)
        expect(user.reload.disabled?).to be false
      end

      it 'disables user' do
        patch "/api/v1/internal/accounts/#{account.id}",
              params: { disable: true },
              headers: { 'X-Internal-Token' => internal_token }

        expect(response).to have_http_status(200)
        expect(user.reload.disabled?).to be true
      end

      it 'returns 404 for non-existent account' do
        patch '/api/v1/internal/accounts/999999',
              params: { email: 'test@example.com' },
              headers: { 'X-Internal-Token' => internal_token }

        expect(response).to have_http_status(404)
      end
    end
  end

  describe 'DELETE /api/v1/internal/accounts' do
    let!(:account) { Fabricate(:account, username: 'todelete') }
    let!(:user) { Fabricate(:user, account: account, email: 'todelete@example.com') }

    context 'with valid internal token' do
      it 'deletes the account by email' do
        delete '/api/v1/internal/accounts',
               params: { email: 'todelete@example.com' },
               headers: { 'X-Internal-Token' => internal_token }

        expect(response).to have_http_status(200)
        json = response.parsed_body
        expect(json['deleted']).to be true
        expect(json['email']).to eq('todelete@example.com')
      end

      it 'returns 404 for non-existent email' do
        delete '/api/v1/internal/accounts',
               params: { email: 'nonexistent@example.com' },
               headers: { 'X-Internal-Token' => internal_token }

        expect(response).to have_http_status(404)
      end
    end
  end

  describe 'POST /api/v1/internal/accounts/:id/approve' do
    let!(:account) { Fabricate(:account) }
    let!(:user) { Fabricate(:user, account: account, approved: false) }

    context 'with valid internal token' do
      it 'approves the account' do
        post "/api/v1/internal/accounts/#{account.id}/approve",
             headers: { 'X-Internal-Token' => internal_token }

        expect(response).to have_http_status(200)
        expect(user.reload.approved?).to be true
      end
    end
  end

  describe 'POST /api/v1/internal/accounts/approve_batch' do
    let!(:pending_users) do
      3.times.map do
        account = Fabricate(:account)
        Fabricate(:user, account: account, approved: false)
      end
    end

    context 'with valid internal token' do
      it 'approves all pending accounts' do
        post '/api/v1/internal/accounts/approve_batch',
             params: { all: true },
             headers: { 'X-Internal-Token' => internal_token }

        expect(response).to have_http_status(200)
        json = response.parsed_body
        expect(json['approved_count']).to eq(3)
        pending_users.each do |user|
          expect(user.reload.approved?).to be true
        end
      end

      it 'approves specified number of accounts' do
        post '/api/v1/internal/accounts/approve_batch',
             params: { number: 2 },
             headers: { 'X-Internal-Token' => internal_token }

        expect(response).to have_http_status(200)
        json = response.parsed_body
        expect(json['approved_count']).to eq(2)
      end

      it 'approves specific account IDs' do
        account_ids = pending_users.first(2).map { |u| u.account_id.to_s }

        post '/api/v1/internal/accounts/approve_batch',
             params: { account_ids: account_ids },
             headers: { 'X-Internal-Token' => internal_token }

        expect(response).to have_http_status(200)
        json = response.parsed_body
        expect(json['approved_count']).to eq(2)
      end

      it 'returns error when no parameter provided' do
        post '/api/v1/internal/accounts/approve_batch',
             headers: { 'X-Internal-Token' => internal_token }

        expect(response).to have_http_status(422)
      end
    end
  end
end
