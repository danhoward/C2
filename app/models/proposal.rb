class Proposal < ActiveRecord::Base
  include WorkflowModel
  include ValueHelper
  include StepManager

  has_paper_trail class_name: 'C2Version'

  CLIENT_MODELS = []  # this gets populated later
  FLOWS = %w(parallel linear).freeze

  workflow do
    state :pending do
      event :approve, transitions_to: :approved
      event :restart, transitions_to: :pending
      event :cancel, transitions_to: :cancelled
    end
    state :approved do
      event :restart, transitions_to: :pending
      event :cancel, transitions_to: :cancelled
      event :approve, transitions_to: :approved do
        halt  # no need to trigger a state transition
      end
    end
    state :cancelled do
      event :approve, transitions_to: :cancelled do
        halt  # can't escape
      end
    end
  end

  acts_as_taggable

  has_many :steps
  has_many :individual_steps, ->{ individual }, class_name: 'Steps::Individual'
  has_many :approvers, through: :individual_steps, source: :user
  has_many :completers, through: :individual_steps, source: :completer
  has_many :api_tokens, through: :individual_steps
  has_many :attachments, dependent: :destroy
  has_many :approval_delegates, through: :approvers, source: :outgoing_delegations
  has_many :comments, dependent: :destroy
  has_many :delegates, through: :approval_delegates, source: :assignee

  has_many :observations, -> { where("proposal_roles.role_id in (select roles.id from roles where roles.name='observer')") }
  has_many :observers, through: :observations, source: :user
  belongs_to :client_data, polymorphic: true, dependent: :destroy
  belongs_to :requester, class_name: 'User'

  delegate :client_slug, to: :client_data, allow_nil: true

  validates :client_data_type, inclusion: {
    in: ->(_) { self.client_model_names },
    message: "%{value} is not a valid client model type. Valid client model types are: #{CLIENT_MODELS.inspect}",
    allow_blank: true
  }
  validates :flow, presence: true, inclusion: {in: FLOWS}
  validates :requester_id, presence: true
  validates :public_id, uniqueness: true, allow_nil: true

  self.statuses.each do |status|
    scope status, -> { where(status: status) }
  end
  scope :closed, -> { where(status: ['approved', 'cancelled']) } #TODO: Backfill to change approvals in 'reject' status to 'cancelled' status
  scope :cancelled, -> { where(status: 'cancelled') }

  FISCAL_YEAR_START_MONTH = 10 # 1-based
  scope :for_fiscal_year, lambda { |year|
    start_time = Time.zone.local(year - 1, FISCAL_YEAR_START_MONTH, 1)
    end_time = start_time + 1.year
    where(created_at: start_time...end_time)
  }

  # @todo - this should probably be the only entry into the approval system
  def root_step
    steps.where(parent: nil).first
  end

  def parallel?
    flow == "parallel"
  end

  def linear?
    flow == "linear"
  end

  def delegate?(user)
    approval_delegates.exists?(assignee_id: user.id)
  end

  def existing_approval_for(user)
    where_clause = <<-SQL
      user_id = :user_id
      OR user_id IN (SELECT assigner_id FROM approval_delegates WHERE assignee_id = :user_id)
      OR user_id IN (SELECT assignee_id FROM approval_delegates WHERE assigner_id = :user_id)
    SQL
    steps.where(where_clause, user_id: user.id).first
  end

  def subscribers
    results = approvers + observers + delegates + [requester]
    results.compact.uniq
  end

  def subscribers_except_delegates
    subscribers - delegates
  end

  def reset_status
    unless cancelled?
      if root_step.nil? || root_step.approved?
        update(status: "approved")
      else
        update(status: "pending")
      end
    end
  end

  def has_subscriber?(user)
    subscribers.include?(user)
  end

  def existing_observation_for(user)
    observations.find_by(user: user)
  end

  def eligible_observers
    if observations.count > 0
      User.where(client_slug: client_slug).where('id not in (?)', observations.pluck('user_id'))
    else
      User.where(client_slug: client_slug)
    end
  end

  def add_observer(email_address, adder=nil, reason=nil)
    user = User.for_email_with_slug(email_address, client_slug)

    # this authz check is here instead of in a Policy because the Policy classes
    # are applied to the current_user, not (as in this case) the user being acted upon.
    if client_data && !client_data.slug_matches?(user) && !user.admin?
      fail Pundit::NotAuthorizedError.new("May not add observer belonging to a different organization.")
    end

    unless existing_observation_for(user)
      create_new_observation(user, adder, reason)
    end
  end

  def add_requester(email)
    user = User.for_email(email)
    if awaiting_approver?(user)
      fail "#{email} is an approver on this Proposal -- cannot also be Requester"
    end
    set_requester(user)
  end

  def set_requester(user)
    update(requester: user)
  end

  def name
    if client_data
      client_data.public_send(:name)
    end
  end

  def fields_for_display
    if client_data
      client_data.public_send(:fields_for_display)
    else
      []
    end
  end

  # Be careful if altering the identifier. You run the risk of "expiring" all
  # pending approval emails
  def version
    [
      updated_at.to_i,
      client_data.try(:version)
    ].compact.max
  end

  def restart
    individual_steps.each(&:restart!)

    if root_step
      root_step.initialize!
    end
    Dispatcher.deliver_new_proposal_emails(self)
  end

  # Returns True if the user is an "active" approver and has acted on the proposal
  def is_active_approver?(user)
    individual_steps.non_pending.exists?(user: user)
  end

  def self.client_model_names
    CLIENT_MODELS.map(&:to_s)
  end

  def self.client_slugs
    CLIENT_MODELS.map(&:client_slug)
  end

  private

  def create_new_observation(user, adder, reason)
    ObservationCreator.new(
      observer: user,
      proposal_id: id,
      reason: reason,
      observer_adder: adder
    ).run
  end
end
