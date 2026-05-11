---
title: Rendering events in a form
layout: default
parent: Events as first-class Rails citizens
grand_parent: Recipes
nav_order: 1
---

# Rendering events in a form
{: .no_toc }

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

To show a message inline next to a specific field, scope the lookup by attribute with the standard `errors[:attr]` API — the same idiom you'd use on any `ActiveRecord` model:

```erb
<div>
  <%= f.label :amount %>
  <%= f.number_field :amount %>
  <% if @event.errors[:amount].any? %>
    <span class="error"><%= @event.errors[:amount].full_messages %></span>
  <% end %>
</div>
```

{: .note }
Funes events actually expose three error collections — `errors`, `own_errors`, and `state_errors` — to keep different failure modes apart. The `errors` used above is the right pick most of the time and the standard Rails idiom. See [Reading the right error collection](/recipes/error-collections/) for when to reach for each.
