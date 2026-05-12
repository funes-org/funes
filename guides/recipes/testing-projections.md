---
title: Testing projections
layout: default
parent: Recipes
nav_order: 8
---

# Testing projections
{: .no_toc }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

Projections are pure functions: given a state and an event, they return a new state. That makes them straightforward to test — one interpretation at a time, without replaying an entire event stream. `Funes::ProjectionTestHelper` ships a small set of methods for exactly that, letting you exercise each part of a projection in isolation.

## Setup

Include `Funes::ProjectionTestHelper` in your test class and bind the projection under test with the `projection` macro:

```ruby
# test/projections/outstanding_balance_projection_test.rb
class OutstandingBalanceProjectionTest < ActiveSupport::TestCase
  include Funes::ProjectionTestHelper

  projection OutstandingBalanceProjection
end
```

That gives you three methods: `interpret`, `initial_state`, and `final_state`. They all use the binding you declared, so you don't have to repeat the projection class on every call.

The helper itself is a plain Ruby module — no test-framework-specific machinery — so the same `include` works in an RSpec example group:

```ruby
# spec/projections/outstanding_balance_projection_spec.rb
RSpec.describe OutstandingBalanceProjection do
  include Funes::ProjectionTestHelper

  projection OutstandingBalanceProjection
end
```

The examples below use minitest assertions, but the helper calls themselves are identical under RSpec — swap in `expect(...)` matchers and you're done.

## Testing event interpretations

`interpret` runs a single `interpretation_for` block in isolation. You pass an event instance and the state you want to start from (via the `given:` keyword). It returns the state produced by that interpretation:

```ruby
test "issuing a debt sets the outstanding balance" do
  event = Debt::Issued.new(amount: 5_000)
  result = interpret(event, given: OutstandingBalance.new)

  assert_instance_of OutstandingBalance, result
  assert_equal 5_000, result.outstanding_balance
end
```

Because `interpret` returns the new state, you can fold a sequence of events with `inject` to simulate an event stream without building one:

```ruby
test "a payment reduces the outstanding balance" do
  events = [ Debt::Issued.new(amount: 5_000),
             Debt::PaymentReceived.new(amount: 1_000) ]
  result = events.inject(OutstandingBalance.new) { |state, event| interpret(event, given: state) }

  assert_equal 4_000, result.outstanding_balance
end
```

### Testing validation side effects

Because `interpret` returns the state object directly, you can assert on validations too:

```ruby
test "balance cannot go negative" do
  state = OutstandingBalance.new(outstanding_balance: 200)
  event = Debt::PaymentReceived.new(amount: 500)
  result = interpret(event, given: state)

  assert_equal(-300, result.outstanding_balance)
  refute result.valid?
end
```

### The `at:` parameter

Every interpretation block receives a temporal reference — the `at` value — alongside the state and event. `interpret` defaults `at:` to `Time.current`, but you can supply a specific time when the interpretation logic depends on it:

```ruby
test "records the payment date" do
  payment_at = Time.new(2024, 3, 15, 12, 0, 0)
  state = OutstandingBalance.new(outstanding_balance: 5_000)
  event = Debt::PaymentReceived.new(amount: 1_000)
  result = interpret(event, given: state, at: payment_at)

  assert_equal payment_at, result.last_payment_at
end
```

Passing a `Date` instead of a `Time` is also supported — Funes coerces it to the beginning of that day.

### Overriding the bound projection

When a single test needs to exercise a different projection, pass it explicitly with the `projection:` keyword:

```ruby
result = interpret(event, given: state, projection: AlternateProjection)
```

`initial_state` and `final_state` accept the same keyword for the same reason.

## Testing initial state

If your projection defines an `initial_state` block, use `initial_state` to test it in isolation:

```ruby
test "initial state starts with a zero balance" do
  assert_equal 0, initial_state.outstanding_balance
end
```

Pass an explicit `at:` when the initial state depends on the temporal reference:

```ruby
test "initial state records the query time" do
  at = Time.new(2024, 1, 1)
  result = initial_state(at: at)

  assert_equal at, result.recorded_as_of
end
```

## Testing final state

If your projection defines a `final_state` block, use `final_state` to test it. Pass the state to finalize via `given:`:

```ruby
test "final state computes days since issuance" do
  state = OutstandingBalance.new(since: Date.new(2024, 1, 1))
  result = final_state(given: state, at: Time.new(2024, 3, 31))

  assert_equal 90, result.days_in_effect
end
```

## Putting it together

The helper hands you three primitives — interpret an event, build the initial state, apply the final state — and stays out of the way after that. How you organize your tests is entirely up to you and the conventions your team already follows. The example below mirrors the projection's structure (one test per event type, plus tests for the initial and final state blocks), but feel free to split across files, group with `describe` blocks, name tests differently, or arrange them in whatever shape reads best:

```ruby
# test/projections/outstanding_balance_projection_test.rb
class OutstandingBalanceProjectionTest < ActiveSupport::TestCase
  include Funes::ProjectionTestHelper

  projection OutstandingBalanceProjection

  test "initial state has zero balance" do
    assert_equal 0, initial_state.outstanding_balance
  end

  test "Debt::Issued sets the balance" do
    result = interpret(Debt::Issued.new(amount: 5_000), given: OutstandingBalance.new)

    assert_equal 5_000, result.outstanding_balance
  end

  test "Debt::PaymentReceived reduces the balance" do
    result = interpret(Debt::PaymentReceived.new(amount: 1_000),
                       given: OutstandingBalance.new(outstanding_balance: 5_000))

    assert_equal 4_000, result.outstanding_balance
  end

  test "final state computes days in effect" do
    state = OutstandingBalance.new(since: Date.new(2024, 1, 1))
    result = final_state(given: state, at: Time.new(2024, 3, 31))

    assert_equal 90, result.days_in_effect
  end
end
```

To understand what a projection does and how to write one, see the [Projection](/concepts/projection/) concept.
