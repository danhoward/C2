# Represents a single user's ability to approve, the "leaves" of an approval
# chain
module Steps
  class Individual < Step
    belongs_to :user
    has_one :api_token, -> { fresh }, foreign_key: "step_id"
    has_many :delegations, through: :user, source: :outgoing_delegations
    has_many :delegates, through: :delegations, source: :assignee

    validate :user_is_not_requester
    validates :user, presence: true
    delegate :full_name, :email_address, to: :user, prefix: true
    scope :with_users, -> { includes :user }

    self.abstract_class = true

    workflow do
      on_transition { self.touch } # sets updated_at; https://github.com/geekq/workflow/issues/96

      state :pending do
        event :initialize, transitions_to: :actionable
      end

      state :actionable do
        event :initialize, transitions_to: :actionable do
          halt  # prevent state transition
        end

        event :approve, transitions_to: :approved
        event :restart, transitions_to: :pending
      end

      state :approved do
        on_entry do
          self.update(approved_at: Time.zone.now)
          self.notify_parent_approved
          Dispatcher.on_approval_approved(self)
        end

        event :initialize, transitions_to: :actionable do
          self.notify_parent_approved
          halt  # prevent state transition
        end

        event :restart, transitions_to: :pending
      end
    end

    protected

    def restart
      self.api_token.try(:expire!)
      super
    end

    def user_is_not_requester
      if user_id && user_id == proposal.requester_id
        errors.add(:user, "Cannot be Requester")
      end
    end
  end
end
