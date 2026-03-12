module Examples
  class DepositEventStream < Funes::EventStream
    consistency_projection Examples::Deposit::ConsistencyProjection
    actual_time_attribute :effective_date

    add_transactional_projection Examples::Deposit::SnapshotProjection
    add_transactional_projection Examples::Deposit::LastActivityProjection
  end
end
