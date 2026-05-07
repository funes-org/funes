---
title: Testing projections
layout: default
parent: Recipes
nav_order: 8
---

# Testing projections
{: .no_toc }

After reading this guide, you will know how to test projection logic in isolation — one interpretation at a time — using the `Funes::ProjectionTestHelper`.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

Projections are pure functions: given a state and an event, they return a new state. That makes them straightforward to test. To make developers life easier, Funes ships `ProjectionTestHelper` — a set of methods that let you exercise each part of a projection independently, without replaying an entire event stream.

## Setup

Include `Funes::ProjectionTestHelper` in your test class:

```ruby
# test/projections/outstanding_balance_projection_test.rb
class OutstandingBalanceProjectionTest < ActiveSupport::TestCase
  include Funes::ProjectionTestHelper
end
```

That gives you three methods: `interpret_event_based_on`, `build_initial_state_based_on`, and `apply_final_state_based_on`.

## Testing event interpretations

`interpret_event_based_on` runs a single `interpretation_for` block in isolation. You pass the projection class, an event instance, and the state you want to start from. It returns the state produced by that interpretation:

```ruby
test "issuing a debt sets the outstanding balance" do
  initial_state = OutstandingBalance.new()
  event = Debt::Issued.new(amount: 5_000)
  result = interpret_event_based_on(OutstandingBalanceProjection, event, initial_state)

  assert_instance_of OutstandingBalance, result
  assert_equal 5_000, result.outstanding_balance
end
```

You can chain calls to simulate a sequence of events without building a full event stream:

```ruby
test "a payment reduces the outstanding balance" do
  prev_state = interpret_event_based_on(OutstandingBalanceProjection,
                                        Debt::Issued.new(amount: 5_000),
                                        OutstandingBalance.new)
  result = interpret_event_based_on(OutstandingBalanceProjection,
                                    Debt::PaymentReceived.new(amount: 1_000),
                                    prev_state)

  assert_equal 4_000, result.outstanding_balance
end
```

### Testing validation side effects

Because `interpret_event_based_on` returns the state object directly, you can assert on validations too:

```ruby
test "balance cannot go negative" do
  state = OutstandingBalance.new(outstanding_balance: 200)
  event = Debt::PaymentReceived.new(amount: 500)
  result = interpret_event_based_on(OutstandingBalanceProjection, event, state)

  assert_equal(-300, result.outstanding_balance)
  refute result.valid?
end
```

### The `at` parameter

Every interpretation block receives a temporal reference — the `at` value — alongside the state and event. `interpret_event_based_on` defaults `at` to `Time.current`, but you can supply a specific time when the interpretation logic depends on it:

```ruby
test "records the payment date" do
  payment_at = Time.new(2024, 3, 15, 12, 0, 0)
  state = OutstandingBalance.new(outstanding_balance: 5_000)
  event = Debt::PaymentReceived.new(amount: 1_000)
  result = interpret_event_based_on(OutstandingBalanceProjection, event, state, payment_at)

  assert_equal payment_at, result.last_payment_at
end
```

Passing a `Date` instead of a `Time` is also supported — Funes coerces it to the beginning of that day.

## Testing initial state

If your projection defines an `initial_state` block, use `build_initial_state_based_on` to test it in isolation:

```ruby
test "initial state starts with a zero balance" do
  result = build_initial_state_based_on(OutstandingBalanceProjection)

  assert_equal 0, result.outstanding_balance
end
```

Pass an explicit `at` when the initial state depends on the temporal reference:

```ruby
test "initial state records the query time" do
  at = Time.new(2024, 1, 1)
  result = build_initial_state_based_on(OutstandingBalanceProjection, at)

  assert_equal at, result.recorded_as_of
end
```

## Testing final state

If your projection defines a `final_state` block, use `apply_final_state_based_on` to test it:

```ruby
test "final state computes days since issuance" do
  state = OutstandingBalance.new(since: Date.new(2024, 1, 1))
  at = Time.new(2024, 3, 31)
  result = apply_final_state_based_on(OutstandingBalanceProjection, state, at)

  assert_equal 90, result.days_in_effect
end
```

## Putting it together

A well-structured projection test file mirrors the projection's structure: one describe block per event type, plus blocks for `initial_state` and `final_state` when they exist:

```ruby
# test/projections/outstanding_balance_projection_test.rb
class OutstandingBalanceProjectionTest < ActiveSupport::TestCase
  include Funes::ProjectionTestHelper

  test "initial state has zero balance" do
    assert_equal 0, build_initial_state_based_on(OutstandingBalanceProjection).outstanding_balance
  end

  test "Debt::Issued sets the balance" do
    result = interpret_event_based_on(OutstandingBalanceProjection,
                                      Debt::Issued.new(amount: 5_000),
                                      OutstandingBalance.new)

    assert_equal 5_000, result.outstanding_balance
  end

  test "Debt::PaymentReceived reduces the balance" do
    result = interpret_event_based_on(OutstandingBalanceProjection,
                                      Debt::PaymentReceived.new(amount: 1_000),
                                      OutstandingBalance.new(outstanding_balance: 5_000))

    assert_equal 4_000, result.outstanding_balance
  end

  test "final state computes days in effect" do
    state = OutstandingBalance.new(since: Date.new(2024, 1, 1))
    result = apply_final_state_based_on(OutstandingBalanceProjection, state, Time.new(2024, 3, 31))

    assert_equal 90, result.days_in_effect
  end
end
```

To understand what a projection does and how to write one, see the [Projection](/concepts/projection/) concept.
