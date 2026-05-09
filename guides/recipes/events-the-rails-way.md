---
title: Events the Rails way
layout: default
parent: Recipes
nav_order: 2
---

# Events the Rails way
{: .no_toc }

After reading this guide, you will know how to define events as `ActiveModel` objects, render them in forms, append them from controllers, read the right error collection when something fails, and translate every label and message into the locale your users read.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

Funes is designed to feel like Rails. The patterns on this page — `ActiveModel` validations, `form_with`, strong parameters, the `persisted?`/`errors` cycle, the same `activemodel.attributes` and `activemodel.errors` I18n keys you already use — are ones you use every day. Recording an event means learning one new concept, not a new framework.

## Defining the event

Events are `ActiveModel` objects — no database table, no migration. You define attributes and validations just as you would on any Rails model:

```ruby
# app/events/debt/issued.rb
module Debt
  class Issued < Funes::Event
    attribute :amount, :decimal
    attribute :interest_rate, :decimal
    attribute :at, :datetime

    validates_presence_of :at
    validates :amount, numericality: { greater_than: 0 }
    validates :interest_rate, numericality: { greater_than_or_equal_to: 0 }
  end
end
```

For a deeper look at what events are and how they differ from ActiveRecord models, see the [Event](/concepts/event/) concept.

## Rendering the form

Since events are `ActiveModel` objects, `form_with` and the standard error helpers work exactly as they do with ActiveRecord. Pass the event as the model and Rails takes care of field population and error display:

```erb
<%# app/views/debts/new.html.erb %>
<%= form_with model: @event, url: debt_events_path do |f| %>
  <% if @event.errors.any? %>
    <ul>
      <% @event.errors.full_messages.each do |message| %>
        <li><%= message %></li>
      <% end %>
    </ul>
  <% end %>

  <div>
    <%= f.label :amount %>
    <%= f.number_field :amount %>
  </div>
  <div>
    <%= f.label :interest_rate, "Interest rate" %>
    <%= f.number_field :interest_rate, step: "0.01" %>
  </div>
  <div>
    <%= f.label :at, "Issued at" %>
    <%= f.datetime_field :at %>
  </div>

  <%= f.submit "Issue debt" %>
<% end %>
```

## Appending from a controller

To record an event, build it and call `.append` on the stream for the relevant entity. The result behaves exactly like saving an ActiveRecord model:

```ruby
# app/controllers/debts_controller.rb
class DebtsController < ApplicationController
  def new
    @event = Debt::Issued.new
  end

  def create
    @event = Debt::Issued.new(event_params)
    event_stream = DebtEventStream.for(debt_id).append(@event)

    if @event.persisted?
      redirect_to debt_path(event_stream) # event streams are routable 
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
      def event_params
        params.require(:debt_issued).permit(:amount, :interest_rate, :at)
      end
      
      def debt_id
        # Your logic to define the stream id - it can use UUID, ULID, nanoid, etc
      end
end
```

`@event.persisted?` returns `true` when the event was written to the log. On failure, the controller re-renders the form and `@event.errors.full_messages` surfaces the validation messages — the same way an invalid ActiveRecord model would.

{: .note }
The string passed to `.for` is the stream identifier — it groups all events for that entity together. You can learn more about how streams work in the [Event Stream](/concepts/event-stream/) concept.

## Reading the right error collection

When an append fails, two independent things can have gone wrong: the event itself can be invalid (`amount` is negative), or the event can be valid but lead to an invalid state once a consistency projection replays it (the payment would exceed what's owed). Funes keeps these two failure modes apart so your form can show the right message in the right place.

Every event exposes three error collections. They all return `ActiveModel::Errors`, so anything you'd do with a Rails model's `errors` works here too.

### `own_errors` — unit-validation failures

`own_errors` carries the errors produced by the event class's own `ActiveModel` validators — the ones you wrote on the event itself. Read it when you want to surface only what the event got wrong before any projection saw it:

```ruby
event = Order::Placed.new(total: -10)
event.valid?
event.own_errors.full_messages
# => ["Total must be greater than 0"]
```

It also includes any errors added inside the event's interpretation blocks via `event.errors.add(...)`, which a consistency projection uses to reject the event explicitly.

### `state_errors` — consistency-projection failures

`state_errors` carries the errors from the consistency projection — the validations that ran on the resulting state, not on the event:

```ruby
event = stream.append(Inventory::ItemShipped.new(quantity: 9999))
event.state_errors.full_messages
# => ["Quantity on hand must be >= 0"]
```

If the event itself is fine but its effect violates a business rule, the message lands here.

### `errors` — both collections, merged

`errors` returns the union of `own_errors` and `state_errors`. State errors are wrapped with a localized prefix (`"Led to invalid state: …"`) so you can tell at a glance which side of the validation rejected them:

```ruby
event = stream.append(Order::Placed.new(total: -10))
event.errors.full_messages
# => ["Total must be greater than 0",
#     "Led to invalid state: Quantity on hand must be >= 0"]
```

This is the collection `form_with` reads when it renders an error summary, and the one to call from a controller when you just want every reason the append failed.

### Choosing the right one

A quick rule of thumb:

- Re-rendering a form? Use `errors` — `form_with` and `errors.full_messages` already do the right thing.
- Highlighting a specific field on the form? Use `own_errors` — you only want the event's own field-level failures, not the cross-cutting state errors.
- Logging or routing a specific failure mode (alerting on overpayments, for example)? Use `state_errors` — they tell you which projection rejected the event.

## Translating attributes and messages

Because events are `ActiveModel` objects, every Rails I18n convention you already use for ActiveRecord models works on them too. There's no Funes-specific machinery to learn — just a couple of extra keys Funes emits when state validation fails.

### Translating attribute names

`form_with model: @event` calls `human_attribute_name` to label every field. Translate event attributes the same way you translate model attributes — under `activemodel.attributes.<event_class>`:

```yaml
# config/locales/pt-BR.yml
pt-BR:
  activemodel:
    attributes:
      debt/issued:
        amount: "Valor"
        interest_rate: "Juros"
        at: "Data de emissão"
```

The class name is the underscored, slash-separated version of the event class — `Debt::Issued` becomes `debt/issued`. With this in place, `<%= f.label :amount %>` renders "Valor" for `pt-BR` and "Amount" for `en`.

### Translating validation messages

Standard `ActiveModel` validators (`presence`, `numericality`, `format`, `inclusion`, …) read their messages from `activemodel.errors.models.<event_class>.attributes.<attribute>.<validator>`. Funes adds nothing on top:

```yaml
# config/locales/pt-BR.yml
pt-BR:
  activemodel:
    errors:
      models:
        debt/issued:
          attributes:
            amount:
              greater_than: "deve ser maior que %{count}"
            at:
              blank: "é obrigatório"
```

`@event.errors.full_messages` returns translated strings the moment the locale is set.

### Funes-specific keys

When the consistency projection rejects an event, Funes prefixes each adjacent-state error with a localized label. The same happens when an event loses an optimistic concurrency race. Both messages live under `funes.events`:

```yaml
# config/locales/pt-BR.yml
pt-BR:
  funes:
    events:
      led_to_invalid_state_prefix: "Levou a um estado inválido"
      racing_condition_on_insert: "O evento atual levou a um estado inválido"
```

After a rejected append, `event.errors.full_messages` includes lines like:

```
Levou a um estado inválido: Saldo deve ser maior ou igual a 0
```

The English defaults ship with the gem; you only need to add a locale file for each language you support.

## Going further

- Coordinate appends with sibling writes via the [Atomic writes](/recipes/atomic-writes/) recipe.
- Attach acting-user and request context to every event with the [Attaching meta information to events](/recipes/attaching-meta-information/) recipe.
