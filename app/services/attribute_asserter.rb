class AttributeAsserter
  attr_accessor :user, :service_provider, :authn_request

  def initialize(user, service_provider, authn_request)
    self.user = user
    self.service_provider = service_provider
    self.authn_request = authn_request
  end

  def build
    attrs = {
      uuid: {
        getter: :uuid,
        name_format: Saml::XML::Namespaces::Formats::NameId::PERSISTENT,
        name_id_format: Saml::XML::Namespaces::Formats::NameId::PERSISTENT
      }
    }
    bundle.map do |attr|
      attrs[attr] = { getter: -> (principal) { principal.active_profile[attr] } }
    end
    if bundle.include? :email
      attrs[:email] = {
        getter: :email,
        name_format: Saml::XML::Namespaces::Formats::NameId::EMAIL_ADDRESS,
        name_id_format: Saml::XML::Namespaces::Formats::NameId::EMAIL_ADDRESS
      }
    end
    user.asserted_attributes = attrs
  end

  def bundle
    if service_provider.attribute_bundle.present?
      service_provider.attribute_bundle
    elsif authn_request_bundle
      authn_request_bundle
    else
      Profile.default_attribute_bundle
    end
  end

  def authn_request_bundle
    # future: SAMLRequest can declare desired attributes
  end
end
      
