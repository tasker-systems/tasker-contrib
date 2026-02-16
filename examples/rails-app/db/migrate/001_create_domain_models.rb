class CreateDomainModels < ActiveRecord::Migration[7.1]
  def change
    enable_extension 'pgcrypto' unless extension_enabled?('pgcrypto')

    # E-commerce orders
    create_table :orders, id: :uuid do |t|
      t.string   :customer_email, null: false
      t.jsonb    :items,          null: false, default: []
      t.decimal  :total,          precision: 12, scale: 2
      t.string   :status,         null: false, default: 'pending'
      t.uuid     :task_uuid

      t.timestamps
    end

    add_index :orders, :customer_email
    add_index :orders, :status
    add_index :orders, :task_uuid, unique: true, where: 'task_uuid IS NOT NULL'

    # Analytics / data pipeline jobs
    create_table :analytics_jobs, id: :uuid do |t|
      t.string   :source,      null: false
      t.string   :dataset_url
      t.string   :status,      null: false, default: 'pending'
      t.uuid     :task_uuid

      t.timestamps
    end

    add_index :analytics_jobs, :source
    add_index :analytics_jobs, :status
    add_index :analytics_jobs, :task_uuid, unique: true, where: 'task_uuid IS NOT NULL'

    # Microservice orchestration requests
    create_table :service_requests, id: :uuid do |t|
      t.string   :user_id
      t.string   :request_type, null: false
      t.string   :status,       null: false, default: 'pending'
      t.jsonb    :result,       default: {}
      t.uuid     :task_uuid

      t.timestamps
    end

    add_index :service_requests, :user_id
    add_index :service_requests, :request_type
    add_index :service_requests, :status
    add_index :service_requests, :task_uuid, unique: true, where: 'task_uuid IS NOT NULL'

    # Compliance / team-scaling checks
    create_table :compliance_checks, id: :uuid do |t|
      t.string   :order_ref,  null: false
      t.string   :namespace,  null: false
      t.string   :status,     null: false, default: 'pending'
      t.uuid     :task_uuid

      t.timestamps
    end

    add_index :compliance_checks, :order_ref
    add_index :compliance_checks, :namespace
    add_index :compliance_checks, :status
    add_index :compliance_checks, :task_uuid, unique: true, where: 'task_uuid IS NOT NULL'
  end
end
