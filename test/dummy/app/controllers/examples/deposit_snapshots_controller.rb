module Examples
  class DepositSnapshotsController < ApplicationController
    def show
      snapshot = Examples::DepositEventStream
                   .for(params[:id])
                   .projected_with(Examples::Deposit::SnapshotProjection,
                                   at: params[:at].present? ? Time.iso8601(params[:at]) : nil,
                                   as_of: params[:as_of].present? ? Time.iso8601(params[:as_of]) : nil)

      render plain: "balance=#{snapshot.balance}"
    end
  end
end
