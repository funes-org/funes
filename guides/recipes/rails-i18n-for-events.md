---
title: Rails I18n for events
layout: default
parent: Recipes
nav_order: 3
---

# Rails I18n for events
{: .no_toc }

After reading this guide, you will know how to translate event attribute names and validation messages using the same I18n keys you already use for ActiveRecord models, plus the small set of keys Funes itself emits.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

Because events are `ActiveModel` objects, every Rails I18n convention you already use for ActiveRecord models works on them too. There's no Funes-specific machinery to learn — just a couple of extra keys Funes emits when state validation fails.

## Translating attribute names

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

## Translating validation messages

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

## Funes-specific keys

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

> **Note:** `state_errors` and `own_errors` give you direct access to each error category before they are merged into `errors`. See the [Event errors](event-errors) recipe for the breakdown.
