---
title: Append events from a controller
layout: default
parent: Events as first-class Rails citizens
grand_parent: Recipes
nav_order: 2
---

# Append events from a controller
{: .no_toc }

To record an event, build it and call `.append` on the stream for the relevant entity. The result behaves like an `ActiveRecord` `save`:

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
- **`if @event.persisted?`** — the same outcome check you'd write as `if @user.save` after a standard `save` call. The branch shape (`if @event.persisted? ... else render :new ... end`) is the one you've written for `ActiveRecord` forms a hundred times. The check catches invalid events and consistency rejections; when a transactional projection fails, `append` raises instead — see [the next section](#rescue-transactional-projection-failures).
- **`redirect_to debt_path(event_stream)`** — event streams plug into Rails URL helpers just like an `ActiveRecord` model. Pass one to `redirect_to`, `link_to`, or any `<resource>_path` helper and Rails resolves the identifier on its own, with no extra wiring.

## Rescue transactional projection failures

The `persisted?` check catches the quiet failures: an invalid event, or an event that the consistency projection rejects. In both cases `append` returns the event with its errors in place — see [Read the right error collection](/recipes/error-collections/).

A transactional projection fails loudly instead. When its materialization fails, `append` raises, and the transaction rolls back — the event never lands in the log. The exception reaches your controller, from `append` and `append!` alike.

The loud failure is deliberate. A failure at this tier signals a bug in the projection or its table, not bad user input. Funes makes the bug visible — it does not bury it in an error collection.

An `append` on a stream with a transactional projection can raise:

- `ActiveRecord::RecordInvalid` — the materialization model failed its validations. Here `error.record` is the materialization model, not the event.
- `Funes::InvalidMaterializationState` — the same failure, on a projection that persists with a custom method.
- `ActiveRecord::StatementInvalid` — the database rejected the projection's write, for example on a constraint violation.

Often the right response is none: let the exception reach your error tracker, like any other bug. When the controller can respond better, put a rescue around the append:

```ruby
# app/controllers/debts_controller.rb
def create
  @event = Debt::Issued.new(event_params)
  debt_stream = DebtEventStream.for(debt_id)

  begin
    debt_stream.append(@event)
  rescue ActiveRecord::RecordInvalid, Funes::InvalidMaterializationState => error
    # error.record is the projection's materialization model, not @event
    return render :new, status: :unprocessable_entity
  end

  if @event.persisted?
    redirect_to debt_path(debt_stream)
  else
    render :new, status: :unprocessable_entity
  end
end
```

After the rescue, `@event.persisted?` returns `false`, and the log holds no trace of the event.
