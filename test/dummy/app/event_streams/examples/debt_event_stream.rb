module Examples
  class DebtEventStream < Funes::EventStream
    set_consistency_projection Examples::DebtSnapshotProjection

    set_transactional_projection Examples::DebtCollectionsProjection
  end
end
