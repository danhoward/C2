module Ncr
  module Mailboxes
    def self.ba61_tier1_budget
      Ncr::WorkOrder.ba61_tier1_budget_mailbox
    end

    def self.ba61_tier2_budget
      Ncr::WorkOrder.ba61_tier2_budget_mailbox
    end

    def self.ba80_budget
      Ncr::WorkOrder.ba80_budget_mailbox
    end

    def self.ool_ba80_budget
      Ncr::WorkOrder.ool_ba80_budget_mailbox
    end
  end
end
