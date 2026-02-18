require 'rails_helper'

RSpec.describe 'Tasker Workflow Integration', type: :request do
  # Worker is started once by config/initializers/tasker.rb when Rails boots.
  # Do NOT call Bootstrap.start! again here — a second call reinitializes
  # Ruby components while keeping the existing Rust worker, which breaks
  # the event dispatch wiring between the FFI bridge and the Rust channels.

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
          namespace: 'customer_success_rb',
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
      expect(body['namespace']).to eq('customer_success_rb')
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
          namespace: 'payments_rb',
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
      expect(body['namespace']).to eq('payments_rb')
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

  # --------------------------------------------------------------------------
  # 5. Task Completion Verification
  #
  # These tests verify the full infrastructure loop: creating tasks through
  # app endpoints, polling the orchestration API, and confirming all steps
  # reach "complete" state. Requires docker-compose services running.
  # --------------------------------------------------------------------------
  describe 'Task Completion Verification', :completion do
    include TaskPolling

    describe 'E-commerce order task dispatches and processes' do
      it 'creates task, dispatches steps, and reaches terminal status' do
        post '/orders', params: {
          order: {
            customer_email: 'completion-test@example.com',
            cart_items: [
              { sku: 'SKU-100', name: 'Completion Widget', quantity: 1, unit_price: 19.99 }
            ],
            payment_token: 'tok_test_success_completion',
            shipping_address: {
              street: '1 Test Ln', city: 'Testville', state: 'OR', zip: '97201', country: 'US'
            }
          }
        }, as: :json

        expect(response).to have_http_status(:created)
        task_uuid = JSON.parse(response.body)['task_uuid']
        expect(task_uuid).to be_present

        task = wait_for_task_completion(task_uuid)

        # Task must fully complete (all steps successful)
        expect(task['status']).to eq('complete'), "Expected task to complete, got: #{task['status']}"
        expect(task['total_steps']).to eq(5)

        # All steps must have reached "complete" state
        steps = task['steps']
        expect(steps.length).to eq(5)
        completed = steps.count { |s| s['current_state'] == 'complete' }
        expect(completed).to eq(5), "Expected all 5 steps to complete, got #{completed}"

        # Handler dispatch works: first step was attempted
        validate_step = steps.find { |s| s['name'] == 'validate_cart' }
        expect(validate_step).to be_present
        expect(validate_step['attempts']).to be >= 1

        puts "  E-commerce task: #{task['status']} (#{completed}/5 steps complete)"
      end
    end

    describe 'Analytics pipeline task dispatches and processes' do
      it 'creates task, dispatches parallel branches, and reaches terminal status' do
        post '/analytics/jobs', params: {
          job: {
            source: 'production',
            date_range: {
              start_date: (Date.current - 7).iso8601,
              end_date: Date.current.iso8601
            },
            filters: {}
          }
        }, as: :json

        expect(response).to have_http_status(:created)
        task_uuid = JSON.parse(response.body)['task_uuid']
        expect(task_uuid).to be_present

        task = wait_for_task_completion(task_uuid)

        expect(task['status']).to eq('complete'), "Expected task to complete, got: #{task['status']}"
        expect(task['total_steps']).to eq(8)

        steps = task['steps']
        step_names = steps.map { |s| s['name'] }

        # Verify the 3 parallel extract steps exist
        %w[extract_sales_data extract_inventory_data extract_customer_data].each do |name|
          expect(step_names).to include(name), "Expected step '#{name}' to be present"
        end

        # At least one extract step was attempted (parallel dispatch works)
        extract_steps = steps.select { |s| s['name'].start_with?('extract_') }
        attempted = extract_steps.count { |s| s['attempts'] > 0 }
        expect(attempted).to be >= 1, 'Expected at least one extract step to be attempted'

        # All steps must have reached "complete" state
        completed = steps.count { |s| s['current_state'] == 'complete' }
        expect(completed).to eq(8), "Expected all 8 steps to complete, got #{completed}"

        puts "  Analytics task: #{task['status']} (#{completed}/8 steps complete)"
      end
    end

    describe 'User registration task dispatches and processes' do
      it 'creates task, dispatches diamond dependency pattern, and reaches terminal status' do
        post '/services/requests', params: {
          request: {
            user_id: 'completion-user-001',
            email: 'completion-reg@example.com',
            name: 'Completion Tester',
            plan: 'pro',
            referral_code: 'REF-ABCD1234',
            marketing_consent: true
          }
        }, as: :json

        expect(response).to have_http_status(:created)
        task_uuid = JSON.parse(response.body)['task_uuid']
        expect(task_uuid).to be_present

        task = wait_for_task_completion(task_uuid)

        expect(task['status']).to eq('complete'), "Expected task to complete, got: #{task['status']}"
        expect(task['total_steps']).to eq(5)

        steps = task['steps']
        step_names = steps.map { |s| s['name'] }

        # Verify diamond dependency: billing + preferences run in parallel after account creation
        %w[create_user_account setup_billing_profile initialize_preferences send_welcome_sequence update_user_status].each do |name|
          expect(step_names).to include(name), "Expected step '#{name}' to be present"
        end

        # All steps must have reached "complete" state
        completed = steps.count { |s| s['current_state'] == 'complete' }
        expect(completed).to eq(5), "Expected all 5 steps to complete, got #{completed}"

        puts "  User registration task: #{task['status']} (#{completed}/5 steps complete)"
      end
    end

    describe 'Customer success refund task dispatches and processes' do
      it 'creates task, dispatches steps, and reaches terminal status' do
        post '/compliance/checks', params: {
          check: {
            namespace: 'customer_success_rb',
            order_ref: 'ORD-20260101-COMP123',
            ticket_id: 'TICKET-COMP-001',
            customer_id: 'CUST-COMP-001',
            refund_amount: 99.99,
            reason: 'defective',
            agent_id: 'agent_completion',
            priority: 'high'
          }
        }, as: :json

        expect(response).to have_http_status(:created)
        task_uuid = JSON.parse(response.body)['task_uuid']
        expect(task_uuid).to be_present

        task = wait_for_task_completion(task_uuid)

        expect(task['status']).to eq('complete'), "Expected task to complete, got: #{task['status']}"
        expect(task['total_steps']).to eq(5)

        # All steps must have reached "complete" state
        completed = task['steps'].count { |s| s['current_state'] == 'complete' }
        expect(completed).to eq(5), "Expected all 5 steps to complete, got #{completed}"

        puts "  Customer success refund task: #{task['status']} (#{completed}/5 steps complete)"
      end
    end

    describe 'Payments refund task dispatches and processes' do
      it 'creates task, dispatches steps, and reaches terminal status' do
        post '/compliance/checks', params: {
          check: {
            namespace: 'payments_rb',
            order_ref: 'ORD-20260101-PAYCOMP',
            payment_id: 'pay_completion_test',
            refund_amount: 50.00,
            currency: 'USD',
            reason: 'duplicate_charge',
            original_transaction_id: 'txn_original_comp',
            idempotency_key: "idem_#{SecureRandom.hex(16)}"
          }
        }, as: :json

        expect(response).to have_http_status(:created)
        task_uuid = JSON.parse(response.body)['task_uuid']
        expect(task_uuid).to be_present

        task = wait_for_task_completion(task_uuid)

        expect(task['status']).to eq('complete'), "Expected task to complete, got: #{task['status']}"
        expect(task['total_steps']).to eq(4)

        # All steps must have reached "complete" state
        completed = task['steps'].count { |s| s['current_state'] == 'complete' }
        expect(completed).to eq(4), "Expected all 4 steps to complete, got #{completed}"

        puts "  Payments refund task: #{task['status']} (#{completed}/4 steps complete)"
      end
    end
  end
end
