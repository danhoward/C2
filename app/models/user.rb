class User < ActiveRecord::Base
  has_paper_trail class_name: 'C2Version'

  validates :client_slug, inclusion: {
    in: ->(_) { Proposal.client_slugs },
    message: "'%{value}' is not in Proposal.client_slugs #{Proposal.client_slugs.inspect}",
    allow_blank: true
  }
  validates :email_address, presence: true, uniqueness: true
  validates_email_format_of :email_address

  has_many :steps, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :observations, dependent: :destroy

  has_many :user_roles, dependent: :destroy
  has_many :roles, through: :user_roles
  has_many :proposals, foreign_key: "requester_id", dependent: :destroy

  has_many :outgoing_delegations, class_name: 'ApprovalDelegate', foreign_key: 'assigner_id'
  has_many :outgoing_delegates, through: :outgoing_delegations, source: :assignee

  def self.active
    where(active: true)
  end

  # this is for user_roles specifically, not proposals or any other objects for which
  # this user might have roles.
  # rubocop:disable Style/PredicateName
  def has_role?(name_or_role)
    if name_or_role.is_a?(Role)
      self.roles.include?(name_or_role)
    else
      self.roles.exists?(name: name_or_role)
    end
  end
  # rubocop:enable Style/PredicateName

  def add_role(name_or_role)
    if name_or_role.is_a?(Role)
      role = name_or_role
    else
      role = Role.find_or_create_by!(name: name_or_role)
    end
    self.user_roles.find_or_create_by!(role: role)
  end

  def self.with_role(role_name)
    User.joins(:roles).where(roles: { name: role_name }).first
  end

  def self.sql_for_role_slug(role, slug)
    self.with_role(role).select(:id).where(client_slug: slug).to_sql
  end

  def full_name
    if first_name.present? && last_name.present?
      "#{first_name} #{last_name}"
    else
      email_address
    end
  end

  def requested_proposals
    Proposal.where(requester_id: self.id)
  end

  def last_requested_proposal
    self.requested_proposals.order('created_at DESC').first
  end

  def add_delegate(other)
    self.outgoing_delegations.create!(assignee: other)
  end

  def delegates_to?(other)
    self.outgoing_delegations.exists?(assignee_id: other.id)
  end

  def client_admin?
    self.has_role?('client_admin')
  end

  def admin?
    has_role?('admin')
  end

  def not_admin?
    !admin?
  end

  def self.for_email(email)
    User.find_by(email_address: email.strip.downcase) || NullUser.new
  end

  def self.for_email_with_slug(email, client_slug)
    user = self.for_email(email)

    if user.client_slug.blank?
      user.client_slug = client_slug
    end

    user
  end

  def self.from_oauth_hash(auth_hash)
    user_data = auth_hash.extra.raw_info.to_hash
    user = self.for_email(user_data["email"])
    user.update_names_if_present(user_data)
    user
  end

  def update_names_if_present(user_data)
    %w(first_name last_name).each do |field|
      attr = field.to_sym
      if user_data[field].present? && self.send(attr).blank?
        update_attributes(attr => user_data[field])
      end
    end
  end

  def role_on(proposal)
    RolePicker.new(self, proposal)
  end

  def requires_profile_attention?
    first_name.blank? || last_name.blank?
  end
end
