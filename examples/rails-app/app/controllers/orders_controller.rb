class OrdersController < ApplicationController
  def create
    order = Order.create!(
      customer_email: order_params[:customer_email],
      items:          order_params[:cart_items],
      status:         'pending'
    )

    # Submit the e-commerce workflow to Tasker
    task = TaskerCore::Client.create_task(
      name:      'ecommerce_order_processing',
      namespace: 'ecommerce',
      context:   {
        customer_email:   order_params[:customer_email],
        cart_items:        order_params[:cart_items],
        payment_token:     order_params[:payment_token],
        shipping_address:  order_params[:shipping_address],
        domain_record_id:  order.id
      }
    )

    order.update!(task_uuid: task['id'], status: 'processing')

    render json: {
      id:        order.id,
      status:    order.status,
      task_uuid: order.task_uuid,
      message:   'Order submitted for processing'
    }, status: :created
  rescue StandardError => e
    Rails.logger.error("Order creation failed: #{e.message}")
    render json: { error: "Order submission failed: #{e.message}" }, status: :unprocessable_entity
  end

  def show
    order = Order.find(params[:id])
    render json: enrich_with_task_status(order)
  end

  private

  def order_params
    params.require(:order).permit(
      :customer_email,
      :payment_token,
      cart_items: [:sku, :name, :quantity, :unit_price],
      shipping_address: [:street, :city, :state, :zip, :country]
    )
  end
end
