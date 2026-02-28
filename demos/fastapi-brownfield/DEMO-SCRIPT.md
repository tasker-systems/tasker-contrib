# Brownfield Workflow Extraction Demo

## Presenter's Guide for Screen Recording (~15 minutes)

This script walks through taking a working FastAPI application and adding Tasker workflow orchestration using AI-assisted MCP tooling. The demo follows the 6-phase brownfield extraction pattern.

---

## Pre-Recording Setup (not on camera)

1. Ensure the demo app is running:
   ```bash
   cd demos/fastapi-brownfield
   uv run uvicorn app.main:app --reload --port 8090
   ```

2. Verify it works:
   ```bash
   curl -s -X POST http://localhost:8090/orders/ \
     -H "Content-Type: application/json" \
     -d '{"customer_email": "test@example.com", "items": [{"sku": "W-1", "name": "Widget", "quantity": 2, "unit_price": 29.99}]}' \
     | python -m json.tool
   ```

3. Open Claude Code in the `demos/fastapi-brownfield/` directory with the Tasker MCP server connected.

4. Ensure the Tasker MCP tools are available (template_generate, template_validate, template_inspect, schema_inspect, schema_compare, handler_generate).

---

## Act 1: The Problem (2 minutes)

**Goal**: Show the audience what exists today and why it could be better.

### Show the route

Open `app/routes/orders.py` and highlight the 5 sequential service calls:

```
Talking point: "Here's our order processing endpoint. When a customer places
an order, we run 5 steps in sequence — validate the cart, charge payment,
reserve inventory, create the order, and send a confirmation email. Every step
runs synchronously in a single HTTP request."
```

### Show the services

Open `app/services/ecommerce.py` and scroll through the functions:

```
Talking point: "The business logic is cleanly separated into pure functions.
Each function takes typed inputs and returns a Pydantic model. This is
well-structured code — but the route calls everything in sequence."
```

### Make a curl call

```bash
curl -s -X POST http://localhost:8090/orders/ \
  -H "Content-Type: application/json" \
  -d '{
    "customer_email": "demo@example.com",
    "items": [
      {"sku": "WIDGET-001", "name": "Blue Widget", "quantity": 2, "unit_price": 29.99},
      {"sku": "GADGET-042", "name": "Red Gadget", "quantity": 1, "unit_price": 49.99}
    ]
  }' | python -m json.tool
```

```
Talking point: "It works. But there are problems hiding in this sequential
approach:
  - Steps 2 and 3 (payment and inventory) run one after the other, even though
    they don't depend on each other
  - If step 4 fails, all the work in steps 1-3 is wasted with no retry
  - We have zero visibility into which step is slow or failing
  - We can't distribute steps across workers

Let's use Tasker's MCP tools to add orchestration without rewriting the
business logic."
```

---

## Act 2: Analyze with the Agent (3 minutes)

**Goal**: The agent reads the code, traces data flow, and proposes a DAG.

### Prompt the agent

```
Analyze the ecommerce order processing code in this application. Look at
app/services/ecommerce.py and app/services/types.py to understand the data
flow between functions. Then propose a Tasker workflow DAG — which functions
become steps, what are the dependencies, and are there any parallelism
opportunities?
```

### Expected agent analysis

The agent should read the service files and produce something like:

```
I've analyzed the 5 service functions and their data flow:

1. validate_cart_items(cart_items) → EcommerceValidateCartResult
   - Root step, no dependencies
   - Returns: validated_items, totals (subtotal, tax, shipping, total)

2. process_payment(payment_token, total) → EcommerceProcessPaymentResult
   - Needs: total from validate_cart
   - Returns: payment_id, transaction_id, authorization_code

3. update_inventory(validated_items) → EcommerceUpdateInventoryResult
   - Needs: validated_items from validate_cart
   - Returns: updated_products, inventory_log_id

4. create_order(cart, payment, inventory, email) → EcommerceCreateOrderResult
   - Needs: results from steps 1, 2, and 3
   - Returns: order_id, order_number, full order details

5. send_confirmation(order, email) → EcommerceSendConfirmationResult
   - Needs: result from step 4
   - Returns: message_id, sent status
```

### The parallelism discovery (the "aha moment")

```
Talking point (highlight this): "The agent noticed something important:
process_payment only needs the TOTAL from validate_cart, and update_inventory
only needs VALIDATED_ITEMS from validate_cart. They don't depend on each other
at all! In our current code they run sequentially by convention, but they
could run in parallel."
```

### Proposed DAG

The agent should propose:

```
Proposed workflow: order_processing (namespace: ecommerce)

Step 1: validate_cart (root)
  Maps to: ecommerce.validate_cart_items()
  Produces: validated_items, item_count, subtotal, tax, tax_rate, shipping, total

Step 2: process_payment [depends: validate_cart]
  Maps to: ecommerce.process_payment()
  Produces: payment_id, transaction_id, authorization_code, amount_charged, status

Step 3: update_inventory [depends: validate_cart]
  Maps to: ecommerce.update_inventory()
  Produces: updated_products, total_items_reserved, inventory_log_id

  ** Steps 2 and 3 run in PARALLEL — both depend only on validate_cart **

Step 4: create_order [depends: process_payment, update_inventory]
  Maps to: ecommerce.create_order()
  Produces: order_id, order_number, status, total_amount

Step 5: send_confirmation [depends: create_order]
  Maps to: ecommerce.send_confirmation()
  Produces: message_id, email_sent, recipient, status
```

```
Talking point: "This is the DAG shape: validate_cart fans out to payment and
inventory in parallel, then create_order fans in waiting for both, and finally
send_confirmation runs as the leaf. We went from a linear pipeline to a
diamond pattern just by analyzing the real data dependencies."
```

---

## Act 3: Generate Template with MCP Tools (3 minutes)

**Goal**: Use the Tasker MCP tools to generate, validate, and inspect the template.

### Step 1: template_generate

Ask the agent to generate the template using the MCP tool. The agent should call `template_generate` with:

- **name**: `order_processing`
- **namespace**: `ecommerce`
- **steps**: 5 steps with the dependencies and outputs from the proposal

```
Talking point: "The agent is calling the template_generate MCP tool. This
takes our proposed step definitions — names, dependencies, output fields —
and produces a valid Tasker template YAML."
```

Show the generated YAML. Key things to point out:
- The `depends_on` for process_payment and update_inventory both reference only validate_cart
- create_order depends on both process_payment and update_inventory (fan-in)
- Each step has a `result_schema` with typed fields matching the service return types

### Step 2: template_validate

```
Talking point: "Now we validate the template. This checks for structural
correctness, dependency cycles, and best practices."
```

The agent calls `template_validate` — should return `valid: true` with no findings.

### Step 3: template_inspect

```
Talking point: "Let's inspect the DAG structure to confirm our topology."
```

The agent calls `template_inspect` — should show:
- **Root step**: validate_cart (no dependencies)
- **Leaf step**: send_confirmation (no dependents)
- **Execution order**: validate_cart → [process_payment, update_inventory] → create_order → send_confirmation
- All steps have result schemas

```
Talking point: "The execution order confirms it — process_payment and
update_inventory are at the same level, meaning Tasker will run them in
parallel. create_order waits for both to complete before running."
```

---

## Act 4: Validate Data Contracts (2 minutes)

**Goal**: Use schema tools to verify the generated contracts match the existing code.

### schema_inspect

Ask the agent to inspect a specific step's schema, e.g., validate_cart:

```
Talking point: "schema_inspect shows us the field-level detail for each step.
Let's look at validate_cart — it produces validated_items (array),
item_count (integer), subtotal (number), tax (number), and so on. These
match exactly what our validate_cart_items() function returns."
```

### schema_compare

Ask the agent to compare connected steps, e.g., validate_cart → process_payment:

```
Talking point: "schema_compare checks whether the data a producer step outputs
is compatible with what a consumer step needs. Here we're verifying that
validate_cart's output contains the fields process_payment expects. The tool
confirms the contracts are compatible."
```

Then compare validate_cart → update_inventory:

```
Talking point: "Same check for the inventory step. The validated_items array
flows through correctly. These schema tools give us confidence that our
generated template matches the real data flow in our existing code."
```

---

## Act 5: Generate Handlers (2 minutes)

**Goal**: Scaffold typed handler wrappers for the existing services.

### handler_generate

Ask the agent to generate Python handlers from the validated template:

```
Talking point: "handler_generate takes our validated template and produces
three files: typed models (Pydantic BaseModel classes), handler functions
(thin wrappers with the @step_handler decorator), and test stubs."
```

Show the generated handler code. Key points:

```python
# Each handler is just a thin wrapper around the existing service function
@step_handler("ecommerce.validate_cart")
def validate_cart(context) -> ValidateCartResult:
    # Calls the EXISTING service function — no business logic here
    return svc.validate_cart_items(context.items)
```

```
Talking point: "Look at how thin these handlers are. Each one is 3-5 lines.
They just call the existing service functions and return typed results.
The business logic in ecommerce.py doesn't change at all."
```

Show the generated types:

```
Talking point: "The generated Pydantic models match our existing types in
services/types.py. In practice, you'd either use the generated ones or map
to your existing types — either way, the contract is typed and validated."
```

Show the generated tests:

```
Talking point: "We also get test scaffolding — one test per handler with
mock dependencies. These are stubs ready for you to fill in with assertions."
```

---

## Act 6: Wire It Up (3 minutes)

**Goal**: Describe the integration changes needed to complete the transformation.

```
Talking point: "We now have everything we need. Let me walk through the 5
changes required to go from our sequential app to an orchestrated one."
```

### Change 1: Add tasker-py dependency

```toml
# pyproject.toml
dependencies = [
    ...
    "tasker-py>=0.1.6",   # Add this line
]
```

### Change 2: Create handlers

```
Place the generated handler code in app/handlers/ecommerce.py. Each handler
wraps an existing service function with Tasker's @step_handler decorator.
```

### Change 3: Add the template

```
Save the generated YAML template to app/config/templates/ecommerce_order_processing.yaml.
This tells Tasker the DAG shape, step dependencies, and expected schemas.
```

### Change 4: Bootstrap the Worker

```python
# app/main.py — add Worker bootstrap in the lifespan
from tasker_core import Worker

@asynccontextmanager
async def lifespan(app: FastAPI):
    worker = Worker.start(handler_packages=["app.handlers"])
    yield
    worker.stop()
```

### Change 5: Update the route

```python
# app/routes/orders.py — replace sequential calls with task submission
from tasker_core.client import TaskerClient

@router.post("/", status_code=202)
async def create_order(request: CreateOrderRequest, db=Depends(get_db)):
    # Create domain record
    order = Order(customer_email=request.customer_email, ...)
    db.add(order)
    await db.flush()

    # Submit to Tasker — returns immediately
    client = TaskerClient(initiator="order-api")
    task = client.create_task(
        "order_processing",
        namespace="ecommerce",
        context={"items": ..., "customer_email": ..., "payment_token": ...},
    )
    order.task_uuid = task.task_uuid
    await db.commit()

    return {"id": order.id, "status": "processing", "task_uuid": task.task_uuid}
```

### The key message

```
Talking point: "Notice what DIDN'T change: app/services/ecommerce.py.
The business logic is exactly the same. Every function, every line of code
that does the actual work — unchanged. We added orchestration AROUND the
existing code, not instead of it.

What we gained:
  - process_payment and update_inventory now run in parallel
  - Every step has independent retry with configurable backoff
  - Step-level observability — we can see which step is running, which failed
  - The route returns 202 immediately instead of blocking for all 5 steps
  - Steps can run on distributed workers

And we got here by having an AI agent analyze our code, use MCP tools to
generate and validate the template, and scaffold the handler wrappers.
The brownfield extraction pattern works the same way regardless of how
complex the workflow is."
```

---

## Closing (1 minute)

```
Talking point: "To recap — we took a working FastAPI app with 5 sequential
service calls and, using Tasker's MCP tools:

  1. Analyzed the code and discovered a parallelism opportunity
  2. Generated a typed workflow template
  3. Validated the data contracts against our existing code
  4. Scaffolded handler wrappers
  5. Identified the 5 minimal changes needed for integration

The services stayed untouched. The business logic is the source of truth.
Tasker adds orchestration around it.

For more complex examples — like an 8-step analytics pipeline with a full
diamond DAG pattern — check out the examples/fastapi-app/ directory in
tasker-contrib. The pattern is the same: analyze, propose, generate,
validate, wire up."
```

---

## Appendix: Sample MCP Tool Calls

These are the exact MCP tool invocations the agent should make during the demo. Use these as a reference if you need to script the demo precisely.

### template_generate call

```
template_generate(
  name: "order_processing",
  namespace: "ecommerce",
  steps: [
    {
      name: "validate_cart",
      description: "Validate cart items and calculate order totals",
      outputs: [
        { name: "validated_items", field_type: "array:object" },
        { name: "item_count", field_type: "integer" },
        { name: "subtotal", field_type: "number" },
        { name: "tax", field_type: "number" },
        { name: "tax_rate", field_type: "number" },
        { name: "shipping", field_type: "number" },
        { name: "total", field_type: "number" },
        { name: "validated_at", field_type: "string" }
      ]
    },
    {
      name: "process_payment",
      description: "Process payment through payment gateway",
      depends_on: ["validate_cart"],
      outputs: [
        { name: "payment_id", field_type: "string" },
        { name: "transaction_id", field_type: "string" },
        { name: "authorization_code", field_type: "string" },
        { name: "amount_charged", field_type: "number" },
        { name: "currency", field_type: "string" },
        { name: "payment_method_type", field_type: "string" },
        { name: "gateway_response", field_type: "string", required: false },
        { name: "status", field_type: "string" },
        { name: "processed_at", field_type: "string" }
      ]
    },
    {
      name: "update_inventory",
      description: "Reserve inventory for validated cart items",
      depends_on: ["validate_cart"],
      outputs: [
        { name: "updated_products", field_type: "array:object" },
        { name: "total_items_reserved", field_type: "integer" },
        { name: "inventory_changes", field_type: "array:object", required: false },
        { name: "inventory_log_id", field_type: "string" },
        { name: "updated_at", field_type: "string" }
      ]
    },
    {
      name: "create_order",
      description: "Create order record aggregating cart, payment, and inventory",
      depends_on: ["process_payment", "update_inventory"],
      outputs: [
        { name: "order_id", field_type: "string" },
        { name: "order_number", field_type: "string" },
        { name: "customer_email", field_type: "string" },
        { name: "item_count", field_type: "integer" },
        { name: "subtotal", field_type: "number" },
        { name: "tax", field_type: "number" },
        { name: "shipping", field_type: "number" },
        { name: "total", field_type: "number" },
        { name: "total_amount", field_type: "number" },
        { name: "payment_id", field_type: "string" },
        { name: "transaction_id", field_type: "string" },
        { name: "authorization_code", field_type: "string" },
        { name: "inventory_log_id", field_type: "string" },
        { name: "status", field_type: "string" },
        { name: "created_at", field_type: "string" },
        { name: "estimated_delivery", field_type: "string" }
      ]
    },
    {
      name: "send_confirmation",
      description: "Send order confirmation email to customer",
      depends_on: ["create_order"],
      outputs: [
        { name: "email_sent", field_type: "boolean" },
        { name: "recipient", field_type: "string" },
        { name: "email_type", field_type: "string", required: false },
        { name: "message_id", field_type: "string" },
        { name: "subject", field_type: "string" },
        { name: "body_preview", field_type: "string", required: false },
        { name: "channel", field_type: "string" },
        { name: "template", field_type: "string" },
        { name: "status", field_type: "string" },
        { name: "sent_at", field_type: "string" }
      ]
    }
  ]
)
```

### template_validate call

```
template_validate(template_yaml: <output from template_generate>)
```

### template_inspect call

```
template_inspect(template_yaml: <output from template_generate>)
```

### schema_inspect call

```
schema_inspect(template_yaml: <output from template_generate>, step_filter: "validate_cart")
```

### schema_compare call

```
schema_compare(
  template_yaml: <output from template_generate>,
  producer_step: "validate_cart",
  consumer_step: "process_payment"
)
```

### handler_generate call

```
handler_generate(template_yaml: <output from template_generate>, language: "python")
```
