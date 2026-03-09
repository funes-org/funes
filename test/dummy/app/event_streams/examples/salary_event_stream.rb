module Examples
  class SalaryEventStream < Funes::EventStream
    actual_time_attribute :effective_date
  end
end
