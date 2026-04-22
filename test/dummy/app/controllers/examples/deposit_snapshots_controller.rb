module Examples
  class DepositSnapshotsController < ApplicationController
    def show
      stream = Examples::DepositEventStream.for(params[:id])
      snapshot = stream.projected_with(Examples::Deposit::SnapshotProjection)

      render plain: "balance=#{snapshot.balance}"
    end
  end
end
