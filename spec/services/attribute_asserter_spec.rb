require 'rails_helper'

RSpec.describe AttributeAsserter do
  include SamlAuthHelper

  let(:ial1_user) { create(:user, :fully_registered) }
  let(:user) { create(:profile, :active, :verified).user }
  let(:biometric_verified_user) { create(:profile, :active, :verified, idv_level: :in_person).user }
  let(:user_session) { {} }
  let(:identity) do
    build(
      :service_provider_identity,
      service_provider: service_provider.issuer,
      session_uuid: SecureRandom.uuid,
    )
  end
  let(:name_id_format) { Saml::Idp::Constants::NAME_ID_FORMAT_PERSISTENT }
  let(:service_provider_ial) { 1 }
  let(:service_provider_aal) { nil }
  let(:service_provider) do
    instance_double(
      ServiceProvider,
      issuer: 'http://localhost:3000',
      ial: service_provider_ial,
      default_aal: service_provider_aal,
      metadata: {},
    )
  end
  let(:raw_sp1_authn_request) do
    sp1_authnrequest = saml_authn_request_url(overrides: { issuer: sp1_issuer })
    CGI.unescape sp1_authnrequest.split('SAMLRequest').last
  end
  let(:raw_aal3_sp1_authn_request) do
    ial1_aal3_authnrequest = saml_authn_request_url(
      overrides: {
        issuer: sp1_issuer,
        authn_context: [
          Saml::Idp::Constants::IAL1_AUTHN_CONTEXT_CLASSREF,
          Saml::Idp::Constants::AAL3_AUTHN_CONTEXT_CLASSREF,
        ],
      },
    )
    CGI.unescape ial1_aal3_authnrequest.split('SAMLRequest').last
  end
  let(:raw_ial1_authn_request) do
    ial1_authn_request_url = saml_authn_request_url(
      overrides: {
        issuer: sp1_issuer,
        authn_context: Saml::Idp::Constants::IAL1_AUTHN_CONTEXT_CLASSREF,
      },
    )
    CGI.unescape ial1_authn_request_url.split('SAMLRequest').last
  end
  let(:raw_vtr_no_proofing_authn_request) do
    vtr_proofing_authn_request = saml_authn_request_url(
      overrides: {
        issuer: sp1_issuer,
        authn_context: 'C1.C2',
      },
    )
    CGI.unescape vtr_proofing_authn_request.split('SAMLRequest').last
  end
  let(:raw_ial2_authn_request) do
    ial2_authnrequest = saml_authn_request_url(
      overrides: {
        issuer: sp1_issuer,
        authn_context: Saml::Idp::Constants::IAL2_AUTHN_CONTEXT_CLASSREF,
      },
    )
    CGI.unescape ial2_authnrequest.split('SAMLRequest').last
  end
  let(:raw_vtr_proofing_authn_request) do
    vtr_proofing_authn_request = saml_authn_request_url(
      overrides: {
        issuer: sp1_issuer,
        authn_context: 'C1.C2.P1',
      },
    )
    CGI.unescape vtr_proofing_authn_request.split('SAMLRequest').last
  end
  let(:raw_ial1_aal3_authn_request) do
    ial1_aal3_authnrequest = saml_authn_request_url(
      overrides: {
        issuer: sp1_issuer,
        authn_context: [
          Saml::Idp::Constants::IAL1_AUTHN_CONTEXT_CLASSREF,
          Saml::Idp::Constants::AAL3_AUTHN_CONTEXT_CLASSREF,
        ],
      },
    )
    CGI.unescape ial1_aal3_authnrequest.split('SAMLRequest').last
  end
  let(:raw_ialmax_authn_request) do
    ialmax_authnrequest = saml_authn_request_url(
      overrides: {
        issuer: sp1_issuer,
        authn_context: [
          Saml::Idp::Constants::IAL1_AUTHN_CONTEXT_CLASSREF,
        ],
        authn_context_comparison: 'minimum',
      },
    )
    CGI.unescape ialmax_authnrequest.split('SAMLRequest').last
  end
  let(:raw_biometric_preferred_ial_authn_request) do
    biometric_preferred_ial_authnrequest = saml_authn_request_url(
      overrides: {
        issuer: sp1_issuer,
        authn_context: [
          Saml::Idp::Constants::IAL2_BIO_PREFERRED_AUTHN_CONTEXT_CLASSREF,
        ],
      },
    )
    CGI.unescape biometric_preferred_ial_authnrequest.split('SAMLRequest').last
  end
  let(:raw_biometric_required_ial_authn_request) do
    biometric_preferred_ial_authnrequest = saml_authn_request_url(
      overrides: {
        issuer: sp1_issuer,
        authn_context: [
          Saml::Idp::Constants::IAL2_BIO_PREFERRED_AUTHN_CONTEXT_CLASSREF,
        ],
      },
    )
    CGI.unescape biometric_preferred_ial_authnrequest.split('SAMLRequest').last
  end
  let(:sp1_authn_request) do
    SamlIdp::Request.from_deflated_request(raw_sp1_authn_request)
  end
  let(:aal3_sp1_authn_request) do
    SamlIdp::Request.from_deflated_request(raw_aal3_sp1_authn_request)
  end
  let(:ial1_authn_request) do
    SamlIdp::Request.from_deflated_request(raw_ial1_authn_request)
  end
  let(:ial2_authn_request) do
    SamlIdp::Request.from_deflated_request(raw_ial2_authn_request)
  end
  let(:vtr_proofing_authn_request) do
    SamlIdp::Request.from_deflated_request(raw_vtr_proofing_authn_request)
  end
  let(:vtr_no_proofing_authn_request) do
    SamlIdp::Request.from_deflated_request(raw_vtr_no_proofing_authn_request)
  end
  let(:ial1_aal3_authn_request) do
    SamlIdp::Request.from_deflated_request(raw_ial1_aal3_authn_request)
  end
  let(:ialmax_authn_request) do
    SamlIdp::Request.from_deflated_request(raw_ialmax_authn_request)
  end
  let(:biometric_preferred_ial_authnrequest) do
    SamlIdp::Request.from_deflated_request(raw_biometric_preferred_ial_authn_request)
  end
  let(:biometric_required_ial_authnrequest) do
    SamlIdp::Request.from_deflated_request(raw_biometric_required_ial_authn_request)
  end
  let(:decrypted_pii) do
    Pii::Attributes.new_from_hash(
      first_name: 'Jåné',
      phone: '1 (888) 867-5309',
      zipcode: '  12345-1234',
      dob: '12/31/1970',
    )
  end

  describe '#build' do
    context 'when an IAL2 request is made' do
      let(:subject) do
        described_class.new(
          user: user,
          name_id_format: name_id_format,
          service_provider: service_provider,
          authn_request: ial2_authn_request,
          decrypted_pii: decrypted_pii,
          user_session: user_session,
        )
      end
      context 'when the user has been proofed without biometric' do
        context 'custom bundle includes email, phone, and first_name' do
          before do
            user.identities << identity
            allow(service_provider.metadata).to receive(:[]).with(:attribute_bundle).
              and_return(%w[email phone first_name])
            subject.build
          end

          it 'includes all requested attributes + uuid' do
            expect(user.asserted_attributes.keys).
              to eq(%i[uuid email phone first_name verified_at aal ial])
          end

          it 'creates getter function' do
            expect(get_asserted_attribute(user, :first_name)).to eq 'Jåné'
          end

          it 'formats the phone number as e164' do
            expect(get_asserted_attribute(user, :phone)).to eq '+18888675309'
          end

          it 'gets UUID (MBUN) from Service Provider' do
            expect(get_asserted_attribute(user, :uuid)).to eq user.last_identity.uuid
          end
        end

        context 'custom bundle includes dob' do
          before do
            user.identities << identity
            allow(service_provider.metadata).to receive(:[]).with(:attribute_bundle).
              and_return(%w[dob])
            subject.build
          end

          it 'formats the dob in an international format' do
            expect(get_asserted_attribute(user, :dob)).to eq '1970-12-31'
          end
        end

        context 'custom bundle includes zipcode' do
          before do
            user.identities << identity
            allow(service_provider.metadata).to receive(:[]).with(:attribute_bundle).
              and_return(%w[zipcode])
            subject.build
          end

          it 'formats zipcode as 5 digits' do
            expect(get_asserted_attribute(user, :zipcode)).to eq '12345'
          end
        end

        context 'bundle includes :ascii' do
          before do
            user.identities << identity
            allow(service_provider.metadata).to receive(:[]).with(:attribute_bundle).
              and_return(%w[email phone first_name ascii])
            subject.build
          end

          it 'skips ascii as an attribute' do
            expect(user.asserted_attributes.keys).
              to eq(%i[uuid email phone first_name verified_at aal ial])
          end

          it 'transliterates attributes to ASCII' do
            expect(get_asserted_attribute(user, :first_name)).to eq 'Jane'
          end
        end

        context 'Service Provider does not specify bundle' do
          before do
            allow(service_provider.metadata).to receive(:[]).with(:attribute_bundle).
              and_return(nil)
            subject.build
          end

          context 'authn request does not specify bundle' do
            it 'only returns uuid, verified_at, aal, and ial' do
              expect(user.asserted_attributes.keys).to eq %i[uuid verified_at aal ial]
            end
          end

          context 'authn request specifies bundle' do
            # rubocop:disable Layout/LineLength
            let(:raw_ial2_authn_request) do
              request_url = saml_authn_request_url(
                overrides: {
                  issuer: sp1_issuer,
                  authn_context: [
                    Saml::Idp::Constants::IAL2_AUTHN_CONTEXT_CLASSREF,
                    "#{Saml::Idp::Constants::REQUESTED_ATTRIBUTES_CLASSREF}first_name:last_name email, ssn",
                    "#{Saml::Idp::Constants::REQUESTED_ATTRIBUTES_CLASSREF}phone",
                  ],
                },
              )
              CGI.unescape(
                request_url.split('SAMLRequest').last,
              )
            end
            # rubocop:enable Layout/LineLength

            it 'uses authn request bundle' do
              expect(user.asserted_attributes.keys).
                to eq(%i[uuid email first_name last_name ssn phone verified_at aal ial])
            end
          end
        end

        context 'Service Provider specifies empty bundle' do
          before do
            allow(service_provider.metadata).to receive(:[]).with(:attribute_bundle).
              and_return([])
            subject.build
          end

          it 'only includes uuid, verified_at, aal, and ial' do
            expect(user.asserted_attributes.keys).to eq(%i[uuid verified_at aal ial])
          end
        end

        context 'custom bundle has invalid attribute name' do
          before do
            allow(service_provider.metadata).to receive(:[]).with(:attribute_bundle).and_return(
              %w[email foo],
            )
            subject.build
          end

          it 'silently skips invalid attribute name' do
            expect(user.asserted_attributes.keys).to eq(%i[uuid email verified_at aal ial])
          end
        end

        context 'x509 attributes included in the SP attribute bundle' do
          before do
            allow(service_provider.metadata).to receive(:[]).with(:attribute_bundle).
              and_return(%w[email x509_subject x509_issuer x509_presented])
            subject.build
          end

          context 'user did not present piv/cac' do
            let(:user_session) do
              {
                decrypted_x509: nil,
              }
            end

            it 'does not include x509_subject, x509_issuer, and x509_presented' do
              expect(user.asserted_attributes.keys).to eq %i[uuid email verified_at aal ial]
            end
          end

          context 'user presented piv/cac' do
            let(:user_session) do
              {
                decrypted_x509: {
                  subject: 'x509 subject',
                  presented: true,
                }.to_json,
              }
            end

            it 'includes x509_subject x509_issuer x509_presented' do
              expected = %i[uuid email verified_at aal ial x509_subject x509_issuer x509_presented]
              expect(user.asserted_attributes.keys).to eq expected
            end
          end
        end
      end
      context 'when the user has been proofed with biometric' do
        let(:user) { biometric_verified_user }
        before do
          user.identities << identity
          subject.build
        end

        it 'asserts IAL2' do
          expected_ial = Saml::Idp::Constants::IAL2_AUTHN_CONTEXT_CLASSREF
          expect(get_asserted_attribute(user, :ial)).to eq expected_ial
        end
      end
    end

    context 'verified user and proofing VTR request' do
      let(:subject) do
        described_class.new(
          user: user,
          name_id_format: name_id_format,
          service_provider: service_provider,
          authn_request: vtr_proofing_authn_request,
          decrypted_pii: decrypted_pii,
          user_session: user_session,
        )
      end

      before do
        user.identities << identity
        allow(service_provider.metadata).to receive(:[]).with(:attribute_bundle).
          and_return(%w[email first_name last_name])
        subject.build
      end

      it 'includes the correct bundle attributes' do
        expect(user.asserted_attributes.keys).to eq(
          [:uuid, :email, :first_name, :last_name, :verified_at, :vot],
        )
        expect(get_asserted_attribute(user, :first_name)).to eq 'Jåné'
        expect(get_asserted_attribute(user, :vot)).to eq 'C1.C2.P1'
      end
    end

    context 'when an IAL1 request is made' do
      let(:subject) do
        described_class.new(
          user: user,
          name_id_format: name_id_format,
          service_provider: service_provider,
          authn_request: sp1_authn_request,
          decrypted_pii: decrypted_pii,
          user_session: user_session,
        )
      end

      context 'when the user has been proofed without biometric comparison' do
        context 'custom bundle includes email, phone, and first_name' do
          before do
            user.identities << identity
            allow(service_provider.metadata).to receive(:[]).with(:attribute_bundle).
              and_return(%w[email phone first_name])
            subject.build
          end

          it 'only includes uuid, email, aal, and ial (no verified_at)' do
            expect(user.asserted_attributes.keys).to eq %i[uuid email aal ial]
          end

          it 'does not create a getter function for IAL1 attributes' do
            expected_email = EmailContext.new(user).last_sign_in_email_address.email
            expect(get_asserted_attribute(user, :email)).to eq expected_email
          end

          it 'gets UUID (MBUN) from Service Provider' do
            expect(get_asserted_attribute(user, :uuid)).to eq user.last_identity.uuid
          end
        end

        context 'custom bundle includes verified_at' do
          before do
            user.identities << identity
            allow(service_provider.metadata).to receive(:[]).with(:attribute_bundle).
              and_return(%w[email verified_at])
            subject.build
          end

          context 'the service provider is ial1' do
            let(:service_provider_ial) { 1 }

            it 'only includes uuid, email, aal, and ial (no verified_at)' do
              expect(user.asserted_attributes.keys).to eq %i[uuid email aal ial]
            end
          end

          context 'the service provider is ial2' do
            let(:service_provider_ial) { 2 }

            it 'includes verified_at' do
              expect(user.asserted_attributes.keys).to eq %i[uuid email verified_at aal ial]
            end
          end
        end

        context 'Service Provider does not specify bundle' do
          before do
            allow(service_provider.metadata).to receive(:[]).with(:attribute_bundle).
              and_return(nil)
            subject.build
          end

          context 'authn request does not specify bundle' do
            it 'only includes uuid, aal, and ial' do
              expect(user.asserted_attributes.keys).to eq %i[uuid aal ial]
            end
          end

          context 'authn request specifies bundle with first_name, last_name, email, ssn, phone' do
            # rubocop:disable Layout/LineLength
            let(:raw_sp1_authn_request) do
              request_url = saml_authn_request_url(
                overrides: {
                  issuer: sp1_issuer,
                  authn_context: [
                    Saml::Idp::Constants::IAL1_AUTHN_CONTEXT_CLASSREF,
                    Saml::Idp::Constants::AAL2_AUTHN_CONTEXT_CLASSREF,
                    "#{Saml::Idp::Constants::REQUESTED_ATTRIBUTES_CLASSREF}first_name:last_name email, ssn",
                    "#{Saml::Idp::Constants::REQUESTED_ATTRIBUTES_CLASSREF}phone",
                  ],
                },
              )
              CGI.unescape(
                request_url.split('SAMLRequest').last,
              )
            end
            # rubocop:enable Layout/LineLength

            it 'only includes uuid, email, aal, and ial' do
              expect(user.asserted_attributes.keys).to eq(%i[uuid email aal ial])
            end
          end
        end

        context 'Service Provider specifies empty bundle' do
          before do
            allow(service_provider.metadata).to receive(:[]).with(:attribute_bundle).
              and_return([])
            subject.build
          end

          it 'only includes UUID, aal, and ial' do
            expect(user.asserted_attributes.keys).to eq(%i[uuid aal ial])
          end
        end

        context 'custom bundle has invalid attribute name' do
          before do
            allow(service_provider.metadata).to receive(:[]).with(:attribute_bundle).and_return(
              %w[email foo],
            )
            subject.build
          end

          it 'silently skips invalid attribute name' do
            expect(user.asserted_attributes.keys).to eq(%i[uuid email aal ial])
          end
        end

        context 'x509 attributes included in the SP attribute bundle' do
          before do
            allow(service_provider.metadata).to receive(:[]).with(:attribute_bundle).
              and_return(%w[email x509_subject x509_issuer x509_presented])
            subject.build
          end

          context 'user did not present piv/cac' do
            let(:user_session) do
              {
                decrypted_x509: nil,
              }
            end

            it 'does not include x509_subject x509_issuer and x509_presented' do
              expect(user.asserted_attributes.keys).to eq %i[uuid email aal ial]
            end
          end

          context 'user presented piv/cac' do
            let(:user_session) do
              {
                decrypted_x509: {
                  subject: 'x509 subject',
                  presented: true,
                }.to_json,
              }
            end

            it 'includes x509_subject x509_issuer and x509_presented' do
              expected = %i[uuid email aal ial x509_subject x509_issuer x509_presented]
              expect(user.asserted_attributes.keys).to eq expected
            end
          end
        end

        context 'request made with a VTR param' do
          let(:subject) do
            described_class.new(
              user: user,
              name_id_format: name_id_format,
              service_provider: service_provider,
              authn_request: vtr_no_proofing_authn_request,
              decrypted_pii: decrypted_pii,
              user_session: user_session,
            )
          end

          before do
            user.identities << identity
            allow(service_provider.metadata).to receive(:[]).with(:attribute_bundle).
              and_return(%w[email])
            subject.build
          end

          it 'includes the correct bundle attributes' do
            expect(user.asserted_attributes.keys).to eq(
              [:uuid, :email, :vot],
            )
            expect(get_asserted_attribute(user, :vot)).to eq 'C1.C2'
          end
        end
      end
      context 'when the user has been proofed with biometric comparison' do
        let(:user) { biometric_verified_user }
        before do
          user.identities << identity
          subject.build
        end

        it 'asserts IAL1' do
          expected_ial = Saml::Idp::Constants::IAL1_AUTHN_CONTEXT_CLASSREF
          expect(get_asserted_attribute(user, :ial)).to eq expected_ial
        end
      end
    end

    context 'verified user and IAL1 AAL3 request' do
      context 'service provider configured for AAL3' do
        let(:service_provider_aal) { 3 }
        let(:subject) do
          described_class.new(
            user: user,
            name_id_format: name_id_format,
            service_provider: service_provider,
            authn_request: aal3_sp1_authn_request,
            decrypted_pii: decrypted_pii,
            user_session: user_session,
          )
        end

        before do
          user.identities << identity
          allow(service_provider.metadata).to receive(:[]).with(:attribute_bundle).
            and_return(%w[email phone first_name])
          subject.build
        end

        it 'asserts AAL3' do
          expected_aal = Saml::Idp::Constants::AAL3_AUTHN_CONTEXT_CLASSREF
          expect(get_asserted_attribute(user, :aal)).to eq expected_aal
        end
      end

      context 'service provider requests AAL3' do
        let(:subject) do
          described_class.new(
            user: user,
            name_id_format: name_id_format,
            service_provider: service_provider,
            authn_request: ial1_aal3_authn_request,
            decrypted_pii: decrypted_pii,
            user_session: user_session,
          )
        end

        before do
          user.identities << identity
          allow(service_provider.metadata).to receive(:[]).with(:attribute_bundle).
            and_return(%w[email phone first_name])
          subject.build
        end

        it 'asserts AAL3' do
          expected_aal = Saml::Idp::Constants::AAL3_AUTHN_CONTEXT_CLASSREF
          expect(get_asserted_attribute(user, :aal)).to eq expected_aal
        end
      end
    end

    context 'IALMAX' do
      context 'service provider requests IALMAX with IAL1 user' do
        let(:service_provider_ial) { 2 }
        let(:subject) do
          described_class.new(
            user: user,
            name_id_format: name_id_format,
            service_provider: service_provider,
            authn_request: ialmax_authn_request,
            decrypted_pii: decrypted_pii,
            user_session: user_session,
          )
        end

        before do
          user.profiles.delete_all
          subject.build
        end

        it 'asserts IAL1' do
          expected_ial = Saml::Idp::Constants::IAL1_AUTHN_CONTEXT_CLASSREF
          expect(get_asserted_attribute(user, :ial)).to eq expected_ial
        end

        it 'does not include proofed attributes' do
          expect(user.asserted_attributes[:first_name]).to eq(nil)
          expect(user.asserted_attributes[:phone]).to eq(nil)
        end
      end

      context 'IAL2 service provider requests IALMAX with IAL2 user' do
        let(:service_provider_ial) { 2 }
        let(:subject) do
          described_class.new(
            user: user,
            name_id_format: name_id_format,
            service_provider: service_provider,
            authn_request: ialmax_authn_request,
            decrypted_pii: decrypted_pii,
            user_session: user_session,
          )
        end

        before do
          user.identities << identity
          allow(service_provider.metadata).to receive(:[]).with(:attribute_bundle).
            and_return(%w[email phone first_name])
          ServiceProvider.find_by(issuer: sp1_issuer).update!(ial: 2)
          subject.build
        end

        it 'asserts IAL2' do
          expected_ial = Saml::Idp::Constants::IAL2_AUTHN_CONTEXT_CLASSREF
          expect(get_asserted_attribute(user, :ial)).to eq expected_ial
        end

        it 'includes proofed attributes' do
          expect(get_asserted_attribute(user, :first_name)).to eq('Jåné')
          expect(get_asserted_attribute(user, :phone)).to eq('+18888675309')
        end
      end
    end

    context 'non-IAL2 service provider requests IALMAX with IAL2 user' do
      let(:service_provider_ial) { 1 }
      let(:subject) do
        described_class.new(
          user: user,
          name_id_format: name_id_format,
          service_provider: service_provider,
          authn_request: ialmax_authn_request,
          decrypted_pii: decrypted_pii,
          user_session: user_session,
        )
      end

      before do
        user.identities << identity
        allow(service_provider.metadata).to receive(:[]).with(:attribute_bundle).
          and_return(%w[email phone first_name])
        ServiceProvider.find_by(issuer: sp1_issuer).update!(ial: 1)
        subject.build
      end

      it 'asserts IAL1' do
        expected_ial = Saml::Idp::Constants::IAL1_AUTHN_CONTEXT_CLASSREF
        expect(get_asserted_attribute(user, :ial)).to eq expected_ial
      end

      it 'does not include proofed attributes' do
        expect(user.asserted_attributes[:first_name]).to eq(nil)
        expect(user.asserted_attributes[:phone]).to eq(nil)
      end
    end

    context 'when biometric IAL preferred is requested' do
      let(:subject) do
        described_class.new(
          user: user,
          name_id_format: name_id_format,
          service_provider: service_provider,
          authn_request: biometric_preferred_ial_authnrequest,
          decrypted_pii: decrypted_pii,
          user_session: user_session,
        )
      end

      context 'when the user has been proofed with biometric' do
        let(:user) { biometric_verified_user }
        before do
          user.identities << identity
          subject.build
        end

        it 'asserts IAL2 with biometric comparison' do
          expected_ial = Saml::Idp::Constants::IAL2_BIO_REQUIRED_AUTHN_CONTEXT_CLASSREF
          expect(get_asserted_attribute(user, :ial)).to eq expected_ial
        end
      end

      context 'when the user has been proofed without biometric' do
        before do
          user.identities << identity
          subject.build
        end

        it 'asserts IAL2 (without biometric comparison)' do
          expected_ial = Saml::Idp::Constants::IAL2_AUTHN_CONTEXT_CLASSREF
          expect(get_asserted_attribute(user, :ial)).to eq expected_ial
        end
      end
    end

    context 'when biometric IAL required is requested' do
      let(:subject) do
        described_class.new(
          user: user,
          name_id_format: name_id_format,
          service_provider: service_provider,
          authn_request: biometric_required_ial_authnrequest,
          decrypted_pii: decrypted_pii,
          user_session: user_session,
        )
      end

      context 'when the user has been proofed with biometric comparison' do
        let(:user) { biometric_verified_user }
        before do
          user.identities << identity
          subject.build
        end

        it 'asserts IAL2 with biometric comparison' do
          expected_ial = Saml::Idp::Constants::IAL2_BIO_REQUIRED_AUTHN_CONTEXT_CLASSREF
          expect(get_asserted_attribute(user, :ial)).to eq expected_ial
        end
      end
    end

    shared_examples 'unverified user' do
      context 'custom bundle does not include email, phone' do
        before do
          allow(service_provider.metadata).to receive(:[]).with(:attribute_bundle).and_return(
            %w[first_name last_name],
          )
          subject.build
        end

        it 'only includes UUID, aal, and ial' do
          expect(ial1_user.asserted_attributes.keys).to eq(%i[uuid aal ial])
        end
      end

      context 'custom bundle includes all_emails' do
        before do
          create(:email_address, user: user)
          allow(service_provider.metadata).to receive(:[]).with(:attribute_bundle).and_return(
            %w[all_emails],
          )
          subject.build
        end

        it 'includes all the user email addresses' do
          all_emails_getter = ial1_user.asserted_attributes[:all_emails][:getter]
          emails = all_emails_getter.call(user)
          expect(emails.length).to eq(2)
          expect(emails).to match_array(user.confirmed_email_addresses.map(&:email))
        end
      end

      context 'custom bundle includes email, phone' do
        before do
          allow(service_provider.metadata).to receive(:[]).with(:attribute_bundle).and_return(
            %w[first_name last_name email phone],
          )
          subject.build
        end

        it 'only includes UUID, email, aal, and ial' do
          expect(ial1_user.asserted_attributes.keys).to eq(%i[uuid email aal ial])
        end
      end
    end

    context 'unverified user and IAL2 request' do
      let(:subject) do
        described_class.new(
          user: ial1_user,
          name_id_format: name_id_format,
          service_provider: service_provider,
          authn_request: ial2_authn_request,
          decrypted_pii: decrypted_pii,
          user_session: user_session,
        )
      end

      it_behaves_like 'unverified user'
    end

    context 'unverified user and LOA1 request' do
      let(:subject) do
        described_class.new(
          user: ial1_user,
          name_id_format: name_id_format,
          service_provider: service_provider,
          authn_request: ial1_authn_request,
          decrypted_pii: decrypted_pii,
          user_session: user_session,
        )
      end

      it_behaves_like 'unverified user'
    end
  end

  def get_asserted_attribute(user, attribute)
    user.asserted_attributes[attribute][:getter].call(user)
  end
end
