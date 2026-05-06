module SpecFailingExamples::PersistMaterializationModelWith
  # Raised by RaisingOnPersistMaterializationModel#persist! to simulate a custom persistence sink
  # that fails at write time (e.g., object storage unreachable, filesystem read-only, third-party
  # API rejection). Funes should let this exception propagate unchanged.
  class PersistFailureError < StandardError; end
end
