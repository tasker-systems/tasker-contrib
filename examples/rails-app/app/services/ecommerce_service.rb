# frozen_string_literal: true

# Service functions return Dry::Struct instances from Types::Ecommerce.
# See Types::Ecommerce in app/services/types.rb for full struct definitions.
#   validate_cart_items    -> Types::Ecommerce::ValidateCartResult
#   process_payment        -> Types::Ecommerce::ProcessPaymentResult
#   update_inventory       -> Types::Ecommerce::UpdateInventoryResult
#   create_order           -> Types::Ecommerce::CreateOrderResult
#   send_confirmation      -> Types::Ecommerce::SendConfirmationResult
module Ecommerce
  module Service
    TAX_RATE = 0.08
    SHIPPING_THRESHOLD = 75.00
    SHIPPING_COST = 9.99
    MAX_QUANTITY_PER_ITEM = 100
    DECLINED_TOKENS = %w[tok_test_declined tok_insufficient_funds tok_expired].freeze
    GATEWAY_ERROR_TOKENS = %w[tok_gateway_error tok_timeout].freeze

    SIMULATED_STOCK = {
      'SKU-001' => 500,
      'SKU-002' => 250,
      'SKU-003' => 100,
      'SKU-004' => 75,
      'SKU-005' => 1000
    }.freeze
    DEFAULT_STOCK = 200

    module_function

    def validate_cart_items(cart_items:, customer_email:)
      raise TaskerCore::Errors::PermanentError.new(
        'Cart is empty',
        error_code: 'EMPTY_CART'
      ) if cart_items.nil? || cart_items.empty?

      raise TaskerCore::Errors::PermanentError.new(
        'Customer email is required',
        error_code: 'MISSING_EMAIL'
      ) if customer_email.blank?

      validated_items = []
      subtotal = 0.0

      cart_items.each do |item|
        sku      = item['sku']
        name     = item['name']
        quantity = item['quantity'].to_i
        price    = item['unit_price'].to_f

        raise TaskerCore::Errors::PermanentError.new(
          "Invalid quantity for #{sku}: #{quantity}",
          error_code: 'INVALID_QUANTITY'
        ) if quantity < 1 || quantity > MAX_QUANTITY_PER_ITEM

        raise TaskerCore::Errors::PermanentError.new(
          "Invalid price for #{sku}: #{price}",
          error_code: 'INVALID_PRICE'
        ) if price <= 0

        line_total = (quantity * price).round(2)
        subtotal += line_total

        validated_items << {
          sku: sku,
          name: name,
          quantity: quantity,
          unit_price: price,
          line_total: line_total,
          available: true,
          validated_at: Time.current.iso8601
        }
      end

      tax = (subtotal * TAX_RATE).round(2)
      shipping = subtotal >= SHIPPING_THRESHOLD ? 0.0 : SHIPPING_COST
      total = (subtotal + tax + shipping).round(2)

      Types::Ecommerce::ValidateCartResult.new(
        validated_items: validated_items,
        item_count: validated_items.size,
        subtotal: subtotal,
        tax: tax,
        tax_rate: TAX_RATE,
        shipping: shipping,
        total: total,
        free_shipping: shipping == 0.0,
        validation_id: SecureRandom.uuid,
        validated_at: Time.current.iso8601
      )
    end

    def process_payment(payment_info:, total:)
      payment_info = payment_info&.deep_symbolize_keys || {}
      payment_token = payment_info[:token]
      payment_method = payment_info[:method] || 'card'

      raise TaskerCore::Errors::PermanentError.new(
        'Payment token is required',
        error_code: 'MISSING_TOKEN'
      ) if payment_token.blank?

      raise TaskerCore::Errors::PermanentError.new(
        'Order total must be greater than zero',
        error_code: 'INVALID_TOTAL'
      ) if total.nil? || total.to_f <= 0

      total = total.to_f

      if DECLINED_TOKENS.include?(payment_token)
        decline_reason = case payment_token
                         when 'tok_test_declined'       then 'Card declined by issuer'
                         when 'tok_insufficient_funds'   then 'Insufficient funds'
                         when 'tok_expired'              then 'Card expired'
                         end
        raise TaskerCore::Errors::PermanentError.new(
          "Payment declined: #{decline_reason}",
          error_code: 'PAYMENT_DECLINED'
        )
      end

      if GATEWAY_ERROR_TOKENS.include?(payment_token)
        raise TaskerCore::Errors::RetryableError.new(
          "Payment gateway temporarily unavailable for token #{payment_token}"
        )
      end

      payment_id = "pay_#{SecureRandom.hex(12)}"
      transaction_id = "txn_#{SecureRandom.hex(12)}"
      authorization_code = "auth_#{SecureRandom.hex(6).upcase}"

      Types::Ecommerce::ProcessPaymentResult.new(
        payment_id: payment_id,
        transaction_id: transaction_id,
        authorization_code: authorization_code,
        amount_charged: total,
        currency: 'USD',
        payment_method_type: payment_method,
        last_four: payment_token.gsub(/[^0-9]/, '').last(4).rjust(4, '0'),
        status: 'completed',
        gateway_response_code: '00',
        processed_at: Time.current.iso8601
      )
    end

    def update_inventory(cart_validation:, customer_info: nil)
      raise TaskerCore::Errors::PermanentError.new(
        'Cart validation data not available',
        error_code: 'MISSING_CART_VALIDATION'
      ) if cart_validation.nil?

      validated_items = cart_validation[:validated_items]

      raise TaskerCore::Errors::PermanentError.new(
        'No validated items found',
        error_code: 'NO_ITEMS'
      ) if validated_items.nil? || validated_items.empty?

      reservation_id = "res_#{SecureRandom.hex(10)}"
      updated_products = []
      inventory_changes = []
      total_reserved = 0
      out_of_stock = []

      validated_items.each do |item|
        item = item.deep_symbolize_keys if item.is_a?(Hash)
        sku = item[:sku] || item[:product_id].to_s
        requested_qty = (item[:quantity] || 0).to_i
        available_stock = SIMULATED_STOCK.fetch(sku, DEFAULT_STOCK)

        if requested_qty > available_stock
          out_of_stock << { sku: sku, requested: requested_qty, available: available_stock }
          next
        end

        remaining_after = available_stock - requested_qty
        reservation_entry_id = "rsv_#{SecureRandom.hex(8)}"

        updated_products << {
          product_id: sku,
          name: item[:name] || sku,
          previous_stock: available_stock,
          new_stock: remaining_after,
          quantity_reserved: requested_qty,
          reservation_id: reservation_entry_id
        }

        inventory_changes << {
          product_id: sku,
          change_type: 'reservation',
          quantity: -requested_qty,
          reason: 'order_checkout',
          timestamp: Time.current.iso8601,
          reservation_id: reservation_entry_id,
          inventory_log_id: "log_#{SecureRandom.hex(6)}"
        }

        total_reserved += requested_qty
      end

      unless out_of_stock.empty?
        raise TaskerCore::Errors::PermanentError.new(
          "Insufficient stock for: #{out_of_stock.map { |o| o[:sku] }.join(', ')}",
          error_code: 'OUT_OF_STOCK'
        )
      end

      inventory_log_id = "log_#{SecureRandom.hex(8)}"

      Types::Ecommerce::UpdateInventoryResult.new(
        updated_products: updated_products,
        total_items_reserved: total_reserved,
        inventory_changes: inventory_changes,
        inventory_log_id: inventory_log_id,
        updated_at: Time.current.iso8601,
        reservation_id: reservation_id,
        reservation_expires_at: (Time.current + 30.minutes).iso8601,
        all_items_reserved: true
      )
    end

    def create_order(cart_validation:, payment_result:, inventory_result:, customer_email:, shipping_address: nil)
      raise TaskerCore::Errors::PermanentError.new(
        'Missing upstream data for order creation',
        error_code: 'MISSING_DEPENDENCIES'
      ) if cart_validation.nil? || payment_result.nil? || inventory_result.nil?

      order_id = "ORD-#{Time.current.strftime('%Y%m%d')}-#{SecureRandom.hex(6).upcase}"
      validated_items = cart_validation[:validated_items] || []

      items_with_details = validated_items.map do |item|
        item = item.deep_symbolize_keys if item.is_a?(Hash)
        {
          sku: item[:sku],
          name: item[:name],
          quantity: item[:quantity],
          unit_price: item[:unit_price],
          line_total: item[:line_total]
        }
      end

      estimated_shipping_days = case shipping_address&.dig(:country)
                                when 'US' then rand(3..7)
                                when 'CA' then rand(5..10)
                                else rand(7..21)
                                end
      estimated_delivery = (Time.current + estimated_shipping_days.days).to_date
      total_amount = cart_validation[:total]

      Types::Ecommerce::CreateOrderResult.new(
        order_id: order_id,
        order_number: "ORD-#{Date.today.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}",
        status: 'confirmed',
        total_amount: total_amount,
        customer_email: customer_email,
        created_at: Time.current.iso8601,
        estimated_delivery: estimated_delivery.iso8601,
        items: items_with_details,
        subtotal: cart_validation[:subtotal],
        tax: cart_validation[:tax],
        shipping: cart_validation[:shipping],
        payment: {
          payment_id: payment_result[:payment_id],
          transaction_id: payment_result[:transaction_id],
          amount_charged: payment_result[:amount_charged],
          status: payment_result[:status]
        },
        inventory: {
          inventory_log_id: inventory_result[:inventory_log_id]
        },
        shipping_address: shipping_address,
        estimated_shipping_days: estimated_shipping_days
      )
    end

    def send_confirmation(order_result:, cart_validation:, customer_email:)
      raise TaskerCore::Errors::PermanentError.new(
        'Order data not available for confirmation',
        error_code: 'MISSING_ORDER_DATA'
      ) if order_result.nil?

      raise TaskerCore::Errors::PermanentError.new(
        'Customer email is required for confirmation',
        error_code: 'MISSING_EMAIL'
      ) if customer_email.blank?

      order_id = order_result[:order_id]
      total = order_result[:total_amount]
      estimated_delivery = order_result[:estimated_delivery]
      item_count = (cart_validation&.dig(:validated_items) || []).size

      message_id = "msg_#{SecureRandom.hex(12)}"
      sent_at = Time.current

      email_subject = "Order Confirmed: #{order_id}"
      email_body_summary = [
        'Thank you for your order!',
        "Order: #{order_id}",
        "Items: #{item_count}",
        "Total: $#{'%.2f' % total.to_f}",
        "Estimated delivery: #{estimated_delivery}",
        'A tracking number will be sent when your order ships.'
      ].join("\n")

      channels = [
        {
          channel: 'email',
          recipient: customer_email,
          subject: email_subject,
          status: 'delivered',
          message_id: message_id,
          sent_at: sent_at.iso8601
        },
        {
          channel: 'in_app',
          notification_id: "notif_#{SecureRandom.hex(8)}",
          status: 'delivered',
          sent_at: sent_at.iso8601
        }
      ]

      Types::Ecommerce::SendConfirmationResult.new(
        email_sent: true,
        recipient: customer_email,
        email_type: 'order_confirmation',
        sent_at: sent_at.iso8601,
        message_id: message_id,
        order_id: order_id,
        notifications_sent: channels,
        email_subject: email_subject,
        email_body_preview: email_body_summary.truncate(200),
        total_channels: channels.size,
        all_delivered: channels.all? { |c| c[:status] == 'delivered' },
        confirmation_sent_at: sent_at.iso8601
      )
    end
  end
end
