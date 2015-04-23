describe "Add attachments" do
  let (:proposal) {
    FactoryGirl.create(:proposal, :with_requester, :with_cart)
  }
  let! (:attachment) { FactoryGirl.create(:attachment, proposal: proposal) }

  before do
    login_as(proposal.requester)
  end

  it "is visible on a cart" do
    visit cart_path(proposal.cart)
    expect(page).to have_content(attachment.file_file_name)
  end

  context "aws" do
    before do
      Paperclip::Attachment.default_options.merge!(
        bucket: 'my-bucket',
        s3_credentials: {
          access_key_id: 'akey',
          secret_access_key: 'skey'
        },
        s3_permissions: :private,
        storage: :s3,
      )
    end
    after do
      Paperclip::Attachment.default_options[:storage] = :filesystem
    end

    it "uses an expiring url with aws" do
      visit cart_path(proposal.cart)
      url = find("#files a")[:href]
      expect(url).to include('my-bucket')
      expect(url).to include('akey')
      expect(url).to include('Expires')
      expect(url).to include('Signature')
      expect(url).not_to include('skey')
    end
  end
end
