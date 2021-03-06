describe "observers" do
  it "allows observers to be added" do
    expect(ObserverMailer).to receive_message_chain(:on_observer_added, :deliver_later)

    work_order = create(:ncr_work_order)
    observer = create(:user, client_slug: 'ncr')
    proposal = work_order.proposal
    login_as(proposal.requester)

    visit "/proposals/#{proposal.id}"
    select observer.email_address, from: 'observation_user_email_address'
    click_on 'Add an Observer'

    expect(page).to have_content("#{observer.full_name} has been added as an observer")

    proposal.reload

    expect(proposal.observers).to include(observer)
  end

  it "allows observers to be added by other observers" do
    proposal = create(:proposal, :with_observer)
    observer1 = proposal.observers.first
    observer2 = create(:user, client_slug: nil)
    login_as(observer1)

    visit "/proposals/#{proposal.id}"
    select observer2.email_address, from: 'observation_user_email_address'
    click_on 'Add an Observer'

    expect(page).to have_content("#{observer2.full_name} has been added as an observer")

    proposal.reload
    expect(proposal.observers.map(&:email_address)).to include(observer2.email_address)

    expect(email_recipients).to eq([observer2.email_address])
  end

  it "allows a user to add a reason when adding an observer" do
    reason = "is the archbishop of banterbury"
    proposal = create(:proposal)
    observer = create(:user, client_slug: nil)
    login_as(proposal.requester)

    visit "/proposals/#{proposal.id}"
    select observer.email_address, from: 'observation_user_email_address'
    fill_in "observation_reason", with: reason
    click_on 'Add an Observer'

    expect(page).to have_content("#{observer.full_name} has been added as an observer")
    proposal.reload

    expect(deliveries.first.body.encoded).to include reason # subscription notification
  end

  it "hides the reason field until a new observer is selected", js: true do
    proposal = create(:proposal)
    observer = create(:user, client_slug: nil)
    login_as(proposal.requester)

    visit "/proposals/#{proposal.id}"
    expect(page).to have_no_field "observation_reason"
    fill_in_selectized('observation_user_email_address', observer.email_address)
    expect(page).to have_field "observation_reason"
    expect(find_field("observation_reason")).to be_visible
  end

  it "disables the submit button until a new observer is selected", js: true do
    proposal = create(:proposal)
    observer = create(:user, client_slug: nil)
    login_as(proposal.requester)

    visit "/proposals/#{proposal.id}"
    submit_button = find("#add_subscriber")
    expect(submit_button).to be_disabled
    fill_in_selectized('observation_user_email_address', observer.email_address)
    expect(submit_button).to_not be_disabled
  end

  it "observer can delete themselves as observer" do
    proposal = create(:proposal)
    observer = create(:user)

    login_as(proposal.requester)
    visit "/proposals/#{proposal.id}"
    select observer.email_address, from: 'observation_user_email_address'
    click_on 'Add an Observer'

    login_as(observer)
    visit "/proposals/#{proposal.id}"
    delete_button = find('table.observers .button_to input[value="Remove"]')
    delete_button.click
    expect(page).to have_content("Removed Observation for ")
  end

  # adapted from http://stackoverflow.com/a/25047358
  def fill_in_selectized(key, *values)
    values.flatten.each do |value|
      page.execute_script("$('##{key}').selectize()[0].selectize.setValue('#{value}')")
    end
  end
end
