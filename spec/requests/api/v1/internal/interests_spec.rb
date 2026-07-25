# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Internal Interests API' do
  let(:internal_token) { 'test-internal-token' }
  let(:headers)        { { 'X-Internal-Token' => internal_token } }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('INTERNAL_API_TOKEN', nil).and_return(internal_token)
  end

  describe 'POST /api/v1/internal/interests' do
    subject { post '/api/v1/internal/interests', params: params, headers: headers }

    let(:params) { { interest: 'politics', tag: 'election' } }

    context 'without a valid token' do
      let(:headers) { { 'X-Internal-Token' => 'wrong' } }

      it 'returns http unauthorized' do
        subject

        expect(response).to have_http_status(401)
      end
    end

    context 'when the internal token is not configured' do
      before do
        allow(ENV).to receive(:fetch).with('INTERNAL_API_TOKEN', nil).and_return(nil)
      end

      it 'returns http service unavailable' do
        subject

        expect(response).to have_http_status(503)
      end
    end

    context 'when neither the interest nor the tag exists' do
      it 'creates both and assigns them', :aggregate_failures do
        subject

        expect(response).to have_http_status(201)
        expect(response.parsed_body).to include(
          'interest' => 'politics',
          'tag' => 'election',
          'interest_created' => true,
          'tag_created' => true,
          'assignment_created' => true
        )
        expect(Interest.find_normalized('politics').tags.pluck(:name)).to eq(['election'])
      end
    end

    context 'when the tag already exists' do
      before { Fabricate(:tag, name: 'election') }

      it 'does not report the tag as created' do
        subject

        expect(response.parsed_body['tag_created']).to be(false)
      end
    end

    context 'when the assignment already exists' do
      before { post '/api/v1/internal/interests', params: params, headers: headers }

      it 'is idempotent', :aggregate_failures do
        subject

        expect(response).to have_http_status(200)
        expect(response.parsed_body['assignment_created']).to be(false)
        expect(InterestTag.count).to eq(1)
      end
    end

    context 'with an invalid tag name' do
      let(:params) { { interest: 'politics', tag: 'not a tag!' } }

      it 'returns 422 and creates nothing', :aggregate_failures do
        subject

        expect(response).to have_http_status(422)
        expect(response.parsed_body['error']).to eq('Invalid tag name')
        expect(Tag.count).to eq(0)
        expect(Interest.count).to eq(0)
      end
    end

    context 'with an invalid interest name' do
      let(:params) { { interest: 'not an interest!', tag: 'election' } }

      it 'returns 422 and creates nothing', :aggregate_failures do
        subject

        expect(response).to have_http_status(422)
        expect(response.parsed_body['error']).to eq('Invalid interest name')
        expect(Interest.count).to eq(0)
      end
    end

    context 'with a differently cased interest name' do
      before { post '/api/v1/internal/interests', params: { interest: 'Politics', tag: 'election' }, headers: headers }

      it 'does not create a duplicate interest' do
        subject

        expect(Interest.count).to eq(1)
      end
    end
  end

  describe 'DELETE /api/v1/internal/interests' do
    subject { delete '/api/v1/internal/interests', params: { interest: 'politics', tag: 'election' }, headers: headers }

    context 'when the assignment exists' do
      before { post '/api/v1/internal/interests', params: { interest: 'politics', tag: 'election' }, headers: headers }

      it 'removes it but keeps the tag and interest', :aggregate_failures do
        subject

        expect(response).to have_http_status(200)
        expect(response.parsed_body['deleted']).to be(true)
        expect(InterestTag.count).to eq(0)
        expect(Interest.count).to eq(1)
        expect(Tag.count).to eq(1)
      end
    end

    context 'when the assignment does not exist' do
      it 'returns http success with deleted false', :aggregate_failures do
        subject

        expect(response).to have_http_status(200)
        expect(response.parsed_body['deleted']).to be(false)
      end
    end
  end

  describe 'POST /api/v1/internal/interests/bulk' do
    subject { post '/api/v1/internal/interests/bulk', params: { assignments: assignments }, headers: headers }

    context 'with valid assignments' do
      let(:assignments) do
        [
          { interest: 'politics', tag: 'election' },
          { interest: 'politics', tag: 'parliament' },
          { interest: 'sports', tag: 'football' },
        ]
      end

      it 'creates every assignment', :aggregate_failures do
        subject

        expect(response).to have_http_status(200)
        expect(response.parsed_body).to include(
          'processed' => 3,
          'assignments_created' => 3,
          'interests_created' => 2,
          'tags_created' => 3,
          'errors' => []
        )
        expect(Interest.find_normalized('politics').tags.pluck(:name)).to match_array(%w(election parliament))
      end
    end

    context 'with a duplicated assignment' do
      let(:assignments) do
        [
          { interest: 'politics', tag: 'election' },
          { interest: 'politics', tag: 'election' },
        ]
      end

      it 'inserts it once' do
        subject

        expect(response.parsed_body['assignments_created']).to eq(1)
      end
    end

    context 'with a partially invalid batch' do
      let(:assignments) do
        [
          { interest: 'politics', tag: 'election' },
          { interest: 'politics', tag: 'not a tag!' },
          { interest: 'politics', tag: 'parliament' },
        ]
      end

      it 'commits the valid rows and reports the invalid one', :aggregate_failures do
        subject

        expect(response).to have_http_status(200)
        expect(response.parsed_body['assignments_created']).to eq(2)
        expect(response.parsed_body['errors'].size).to eq(1)
        expect(response.parsed_body['errors'].first).to include('index' => 1, 'error' => 'Invalid tag name')
        expect(Interest.find_normalized('politics').tags.pluck(:name)).to match_array(%w(election parliament))
      end
    end

    context 'with more than the maximum number of assignments' do
      let(:assignments) { Array.new(1001) { |i| { interest: 'politics', tag: "tag#{i}" } } }

      it 'returns http unprocessable entity' do
        subject

        expect(response).to have_http_status(422)
      end
    end

    context 'when assignments is not an array' do
      let(:assignments) { 'nope' }

      it 'returns http unprocessable entity' do
        subject

        expect(response).to have_http_status(422)
      end
    end
  end

  describe 'GET /api/v1/internal/interests/:name/tags' do
    subject { get '/api/v1/internal/interests/politics/tags', headers: headers }

    context 'when the interest exists' do
      before do
        post '/api/v1/internal/interests/bulk',
             params: { assignments: [{ interest: 'politics', tag: 'election' }, { interest: 'politics', tag: 'parliament' }] },
             headers: headers
      end

      it 'returns every tag unpaginated', :aggregate_failures do
        subject

        expect(response).to have_http_status(200)
        expect(response.parsed_body['tags_count']).to eq(2)
        expect(response.parsed_body['tags']).to match_array(%w(election parliament))
      end
    end

    context 'when the interest does not exist' do
      it 'returns http not found' do
        subject

        expect(response).to have_http_status(404)
      end
    end
  end
end
