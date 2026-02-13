require 'rails_helper'

RSpec.describe 'Tasker Workflow Integration', type: :request do
  before(:all) do
    # Bootstrap the Tasker worker FFI bridge for tests.
    # In a real deployment this happens in config/initializers/tasker.rb.
    TaskerCore::Worker::Bootstrap.start!
  end

  # --------------------------------------------------------------------------
  # 1. E-commerce Order Processing (linear pipeline)
  # --------------------------------------------------------------------------
  describe 'E-commerce Order Processing' do
    let(:order_payload) do
      {
        order: {
          customer_email: 'buyer@example.com',
          cart_items: [
            { sku: 'SKU-001', name: 'Widget A', quantity: 2, unit_price: 29.99 },
            { sku: 'SKU-003', name: 'Doohickey C', quantity: 1, unit_price: 49.99 }
          ],
          payment_token: 'tok_test_success_4242',
          shipping_address: {
            street: '123 Main St',
            city: 'Portland',
            state: 'OR',
            zip: '97201',
            country: 'US'
          }
        }
      }
    end

    it 'submits an order and returns a task reference' do
      post '/orders', params: order_payload, as: :json

      expect(response).to have_http_status(:created)

      body = JSON.parse(response.body)
      expect(body['id']).to be_present
      expect(body['task_uuid']).to be_present
      expect(body['status']).to eq('processing')
    end

    it 'retrieves order status with task enrichment' do
      post '/orders', params: order_payload, as: :json
      order_id = JSON.parse(response.body)['id']

      get "/orders/#{order_id}", as: :json

      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)
      expect(body['id']).to eq(order_id)
      expect(body).to have_key('task_status')
    end
  end

  # --------------------------------------------------------------------------
  # 2. Analytics Data Pipeline (DAG with parallel branches)
  # --------------------------------------------------------------------------
  describe 'Analytics Data Pipeline' do
    let(:pipeline_payload) do
      {
        job: {
          source: 'production',
          date_range: {
            start_date: (Date.current - 30).iso8601,
            end_date: Date.current.iso8601
          },
          filters: {
            region: 'northeast'
          }
        }
      }
    end

    it 'submits a pipeline job and returns a task reference' do
      post '/analytics/jobs', params: pipeline_payload, as: :json

      expect(response).to have_http_status(:created)

      body = JSON.parse(response.body)
      expect(body['id']).to be_present
      expect(body['task_uuid']).to be_present
      expect(body['source']).to eq('production')
      expect(body['status']).to eq('running')
    end

    it 'retrieves pipeline job status' do
      post '/analytics/jobs', params: pipeline_payload, as: :json
      job_id = JSON.parse(response.body)['id']

      get "/analytics/jobs/#{job_id}", as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['id']).to eq(job_id)
    end
  end

  # --------------------------------------------------------------------------
  # 3. User Registration (diamond dependency pattern)
  # --------------------------------------------------------------------------
  describe 'User Registration Workflow' do
    let(:registration_payload) do
      {
        request: {
          user_id: 'new-user-001',
          email: 'newuser@example.com',
          name: 'Jane Smith',
          plan: 'pro',
          referral_code: 'REF-ABC12345',
          marketing_consent: true
        }
      }
    end

    it 'submits a registration and returns a task reference' do
      post '/services/requests', params: registration_payload, as: :json

      expect(response).to have_http_status(:created)

      body = JSON.parse(response.body)
      expect(body['id']).to be_present
      expect(body['task_uuid']).to be_present
      expect(body['request_type']).to eq('user_registration')
      expect(body['status']).to eq('in_progress')
    end

    it 'retrieves registration status' do
      post '/services/requests', params: registration_payload, as: :json
      request_id = JSON.parse(response.body)['id']

      get "/services/requests/#{request_id}", as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['id']).to eq(request_id)
    end
  end

  # --------------------------------------------------------------------------
  # 4a. Customer Success Refund (team-scaling: customer_success namespace)
  # --------------------------------------------------------------------------
  describe 'Customer Success Refund Workflow' do
    let(:cs_refund_payload) do
      {
        check: {
          namespace: 'customer_success',
          order_ref: 'ORD-20260101-ABC123',
          ticket_id: 'TICKET-9001',
          customer_id: 'CUST-12345',
          refund_amount: 149.99,
          reason: 'defective',
          agent_id: 'agent_42',
          priority: 'high'
        }
      }
    end

    it 'submits a customer success refund check' do
      post '/compliance/checks', params: cs_refund_payload, as: :json

      expect(response).to have_http_status(:created)

      body = JSON.parse(response.body)
      expect(body['id']).to be_present
      expect(body['task_uuid']).to be_present
      expect(body['namespace']).to eq('customer_success')
    end

    it 'retrieves refund check status' do
      post '/compliance/checks', params: cs_refund_payload, as: :json
      check_id = JSON.parse(response.body)['id']

      get "/compliance/checks/#{check_id}", as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['id']).to eq(check_id)
    end
  end

  # --------------------------------------------------------------------------
  # 4b. Payments Refund (team-scaling: payments namespace)
  # --------------------------------------------------------------------------
  describe 'Payments Refund Workflow' do
    let(:payments_refund_payload) do
      {
        check: {
          namespace: 'payments',
          order_ref: 'ORD-20260101-DEF456',
          payment_id: 'pay_abc123def456',
          refund_amount: 75.50,
          currency: 'USD',
          reason: 'duplicate_charge',
          original_transaction_id: 'txn_original_789',
          idempotency_key: "idem_#{SecureRandom.hex(16)}"
        }
      }
    end

    it 'submits a payments refund check' do
      post '/compliance/checks', params: payments_refund_payload, as: :json

      expect(response).to have_http_status(:created)

      body = JSON.parse(response.body)
      expect(body['id']).to be_present
      expect(body['task_uuid']).to be_present
      expect(body['namespace']).to eq('payments')
    end

    it 'retrieves payments refund status' do
      post '/compliance/checks', params: payments_refund_payload, as: :json
      check_id = JSON.parse(response.body)['id']

      get "/compliance/checks/#{check_id}", as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['id']).to eq(check_id)
    end
  end
end
