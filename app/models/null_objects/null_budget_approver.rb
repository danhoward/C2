class NullBudgetApprover
  def initialize(name)
    @name = name
  end

  def email_address
  end

  private

  attr_reader :name
end
