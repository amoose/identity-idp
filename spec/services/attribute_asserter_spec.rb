require 'rails_helper'

describe AttributeAsserter do
  include SamlAuthHelper

  let(:user) do
    user = create(:user, :signed_up)
    user.profiles.create(
      active: true,
      activated_at: Time.current,
      verified_at: Time.current,
      first_name: 'Jane'
    )
    user
  end
  let(:service_provider) { ServiceProvider.new(sp1_saml_settings.issuer) }
  let(:subject) { described_class.new( user, service_provider, sp1_authnrequest ) }

  describe '#build' do
    it 'sets user asserted_attributes' do
      subject.build
      expect(user.asserted_attributes).to have_key :first_name
    end
  end
end
