---
title: Rendering 404s from empty streams
layout: default
parent: Events as first-class Rails citizens
grand_parent: Recipes
nav_order: 3
---

# Rendering 404s from empty streams
{: .no_toc }

`projected_with` mirrors `ActiveRecord#find` end to end. On a hit it returns an instance of the projection's materialization model, ready for the view to render. On a miss it raises `ActiveRecord::RecordNotFound` — and because Rails already maps that exception to a 404 response, a `show` action that calls `projected_with` renders the host app's 404 page with no rescue code, no helper layer, no custom controller plumbing.

```ruby
# app/controllers/debts_controller.rb
class DebtsController < ApplicationController
  def show
    @debt = DebtEventStream.for(params[:id]).projected_with(DebtProjection)
  end
end
```

`@debt` is whatever `DebtProjection` materializes — an `ActiveRecord` row or an `ActiveModel` instance. Whatever shape the projection produces is the same shape the view receives, so the rest of the `show` template is straight Rails.

A miss can come from any of three places: an unknown stream id, a known stream with no events, or a known stream whose events all fall outside the `as_of:` / `at:` window you asked for.

```ruby
DebtEventStream.for("unknown-id").projected_with(DebtProjection)
# => raises ActiveRecord::RecordNotFound

stream = DebtEventStream.for("debt-123")
stream.projected_with(DebtProjection, at: Time.new(1999, 1, 1))
# => raises ActiveRecord::RecordNotFound if every event occurred after Jan 1, 1999
```

Funes also writes a `Rails.logger.info` line before raising, so your logs record which stream, projection, and filter values led to the empty result.
