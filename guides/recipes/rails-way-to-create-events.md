---
title: Rails way to create events/streams
layout: default
parent: Recipes
nav_order: 2
---

# Rails way to create events/streams
{: .no_toc }

After reading this guide, you will know how to record an event in a Rails application — and see how naturally it fits alongside the patterns you already use.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

Funes is designed to feel like Rails. The patterns on this page — `ActiveModel` validations, `form_with`, strong parameters, the `persisted?`/`errors` cycle — are ones you use every day. Recording an event means learning one new concept, not a new framework.

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

For a deeper look at what events are and how they differ from ActiveRecord models, see the [Event](../concepts/event) concept.

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

> **Note:** The string passed to `.for` is the stream identifier — it groups all events for that entity together. You can learn more about how streams work in the [Event Stream](../concepts/event-stream) concept.

## Going further

- Translate event attributes and error messages with the [Rails I18n for events](rails-i18n-for-events) recipe.
- Distinguish unit-validation errors from consistency-projection errors with the [Event errors](event-errors) recipe.
- Coordinate appends with sibling writes via the [Atomic writes](atomic-writes) recipe.
