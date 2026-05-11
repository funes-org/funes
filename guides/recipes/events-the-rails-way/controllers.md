---
title: Appending events from a controller
layout: default
parent: Events as first-class Rails citizens
grand_parent: Recipes
nav_order: 2
---

# Appending events from a controller
{: .no_toc }

To record an event, build it and call `.append` on the stream for the relevant entity. The result behaves exactly like saving an `ActiveRecord` model:

```ruby
# app/controllers/debts_controller.rb
class DebtsController < ApplicationController
  def new
    @event = Debt::Issued.new
  end

  def create
    @event = Debt::Issued.new(event_params)
    debt_stream = DebtEventStream.for(debt_id)
    debt_stream.append(@event)

    if @event.persisted?
      redirect_to debt_path(debt_stream)
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

Four lines in this controller are pure Rails idiom — nothing about events forces you to learn a new pattern:

- **`Debt::Issued.new` in `new`** — the same shape as `User.new` or `Order.new` in any controller. The event class IS the model you hand to the form; there's no `Funes::` factory in the way.
- **`params.require(:debt_issued).permit(:amount, :interest_rate, :at)`** — strong parameters work as-is. The event class name is the param key, and the permitted attributes are the same ones you declared on the event class. Funes plugs straight into `ActionController::StrongParameters`.
- **`if @event.persisted?`** — the same outcome check you'd write as `if @user.save` after a standard `save` call. The branch shape (`if @event.persisted? ... else render :new ... end`) is the one you've written for `ActiveRecord` forms a hundred times.
- **`redirect_to debt_path(event_stream)`** — event streams plug into Rails URL helpers just like an `ActiveRecord` model. Pass one to `redirect_to`, `link_to`, or any `<resource>_path` helper and Rails resolves the identifier on its own, with no extra wiring.
