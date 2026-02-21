# frozen_string_literal: true

# Asynchronous job that creates a Tasker workflow task for an order.
#
# Demonstrates the background job pattern: controller saves the record,
# enqueues this job, and returns 202 immediately. The job then creates
# the Tasker task and updates the order with the task UUID.
class CreateOrderTaskJob < ApplicationJob
  queue_as :default

  def perform(order_id)
    order = Order.find(order_id)

    task = TaskerCore::Client.create_task(
      name: 'ecommerce_order_processing',
      namespace: 'ecommerce_rb',
      context: {
        customer_email: order.customer_email,
        cart_items: order.items,
        payment_info: { token: 'tok_background', method: 'card' },
        domain_record_id: order.id
      }
    )

    order.update!(task_uuid: task.task_uuid, status: 'processing')
    Rails.logger.info("Background: created task #{task.task_uuid} for order #{order.id}")
  rescue StandardError => e
    Rails.logger.error("Background: failed to create task for order #{order_id}: #{e.message}")
    Order.find_by(id: order_id)&.update(status: 'task_creation_failed')
  end
end
