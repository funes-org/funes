module Examples
  class DebtEventStream < Funes::EventStream
    consistency_projection Examples::DebtSnapshotProjection

    add_transactional_projection Examples::DebtCollectionsProjection
    # add_async_projection Examples::DebtCollectionsProjection
  end
end
