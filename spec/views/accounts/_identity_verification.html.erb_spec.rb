require 'rails_helper'

RSpec.describe 'accounts/_identity_verification.html.erb' do
  let(:vtr) { ['C2'] }
  let(:sp_name) { nil }
  let(:authn_context) do
    AuthnContextResolver.new(
      user:,
      service_provider: nil,
      vtr: vtr,
      acr_values: nil,
    ).result
  end
  let(:user) { build(:user) }
  subject(:rendered) { render partial: 'accounts/identity_verification' }

  before do
    @presenter = AccountShowPresenter.new(
      decrypted_pii: nil,
      sp_session_request_url: nil,
      authn_context:,
      sp_name:,
      user:,
      locked_for_session: false,
    )
  end

  context 'with user pending gpo verification' do
    let(:gpo_sp_name) { 'GPO SP' }
    let(:gpo_sp_issuer) { 'urn:gov:gsa:openidconnect:sp:gpo_sp' }
    let(:gpo_sp) { create(:service_provider, issuer: gpo_sp_issuer, friendly_name: gpo_sp_name) }
    let(:user) { create(:user, :with_pending_gpo_profile) }

    before do
      gpo_sp
      user.pending_profile.update(initiating_service_provider_issuer: gpo_sp_issuer)
    end

    it 'references initiating sp with prompt to finish verifying their identity' do
      expect(rendered).to have_content(
        strip_tags(t('account.index.verification.finish_verifying_html', sp_name: gpo_sp_name)),
      )
    end
  end

  context 'with user pending ipp verification' do
    let(:ipp_sp_name) { 'IPP SP' }
    let(:ipp_sp_issuer) { 'urn:gov:gsa:openidconnect:sp:ipp_sp' }
    let(:ipp_sp) { create(:service_provider, issuer: ipp_sp_issuer, friendly_name: ipp_sp_name) }
    let(:user) { build(:user, :with_pending_in_person_enrollment) }

    before do
      ipp_sp
      user.pending_profile.update(initiating_service_provider_issuer: ipp_sp_issuer)
    end

    it 'references initiating sp with prompt to finish verifying their identity' do
      expect(rendered).to have_content(
        strip_tags(t('account.index.verification.finish_verifying_html', sp_name: ipp_sp_name)),
      )
    end
  end

  context 'with partner requesting non-biometric verification' do
    let(:sp_name) { 'Example SP' }
    let(:vtr) { ['C2.P1'] }

    context 'with unproofed user' do
      let(:user) { build(:user) }

      it 'shows unverified badge' do
        expect(rendered).to have_content(t('account.index.verification.unverified_badge'))
      end

      it 'shows warning alert instructing user to complete identity verificaton' do
        expect(rendered).to have_css('.usa-alert.usa-alert--warning')
        expect(rendered).to have_content(
          strip_tags(t('account.index.verification.finish_verifying_html', sp_name:)),
        )
        expect(rendered).to have_link(t('account.index.verification.continue_idv'), href: idv_path)
      end
    end

    context 'with user pending ipp verification' do
      let(:user) { build(:user, :with_pending_in_person_enrollment) }

      it 'shows pending badge' do
        expect(rendered).to have_content(t('account.index.verification.pending_badge'))
      end

      it 'shows content explaining that the user needs to finish verifying their identity' do
        expect(rendered).to have_content(
          strip_tags(t('account.index.verification.finish_verifying_html', sp_name:)),
        )
        expect(rendered).to have_link(
          t('account.index.verification.learn_more_link'),
          href: help_center_redirect_path(
            category: 'verify-your-identity',
            article: 'overview',
            flow: :account_show,
            location: :idv,
          ),
        )
      end

      it 'shows info alert instructing user to go to the post office to complete verification' do
        expect(rendered).to have_css('.usa-alert.usa-alert--info')
        expect(rendered).to have_content(
          strip_tags(
            t(
              'account.index.verification.in_person_instructions_html',
              deadline: @presenter.formatted_ipp_due_date,
            ),
          ),
        )
        expect(rendered).to have_link(
          t('account.index.verification.show_bar_code', app_name: APP_NAME),
          href: idv_in_person_ready_to_verify_url,
        )
      end
    end

    context 'with user pending gpo verification' do
      let(:user) { create(:user, :with_pending_gpo_profile) }

      it 'shows pending badge' do
        expect(rendered).to have_content(t('account.index.verification.pending_badge'))
      end

      it 'shows content explaining that the user needs to finish verifying their identity' do
        expect(rendered).to have_content(
          strip_tags(t('account.index.verification.finish_verifying_html', sp_name:)),
        )
        expect(rendered).to have_link(
          t('account.index.verification.learn_more_link'),
          href: help_center_redirect_path(
            category: 'verify-your-identity',
            article: 'overview',
            flow: :account_show,
            location: :idv,
          ),
        )
      end

      it 'shows info alert instructing user to enter their gpo verification code' do
        expect(rendered).to have_css('.usa-alert.usa-alert--info')
        expect(rendered).to have_content(t('account.index.verification.instructions'))
        expect(rendered).to have_link(
          t('account.index.verification.reactivate_button'),
          href: idv_verify_by_mail_enter_code_path,
        )
      end
    end

    context 'with non-biometric proofed user' do
      let(:user) { build(:user, :proofed) }

      it 'shows verified badge' do
        expect(rendered).to have_content(t('account.index.verification.verified_badge'))
      end

      it 'shows content confirming verified identity' do
        expect(rendered).to have_content(
          strip_tags(
            t('account.index.verification.you_verified_your_identity_html', sp_name: APP_NAME),
          ),
        )
        expect(rendered).to have_link(
          t('account.index.verification.learn_more_link'),
          href: help_center_redirect_path(
            category: 'verify-your-identity',
            article: 'overview',
            flow: :account_show,
            location: :idv,
          ),
        )
      end

      it 'renders pii' do
        expect(rendered).to render_template(partial: 'accounts/_pii')
      end

      context 'with initiating sp for active profile' do
        let(:sp_name) { 'Example SP' }
        let(:sp_issuer) { 'urn:gov:gsa:openidconnect:sp:example_sp' }
        let(:sp) { create(:service_provider, issuer: sp_issuer, friendly_name: sp_name) }

        before do
          sp
          user.active_profile.update(initiating_service_provider_issuer: sp_issuer)
        end

        it 'shows content confirming verified identity for initiating sp' do
          expect(rendered).to have_content(
            strip_tags(
              t('account.index.verification.you_verified_your_identity_html', sp_name:),
            ),
          )
        end
      end
    end
  end

  context 'with partner requesting biometric verification' do
    let(:sp_name) { 'Example SP' }
    let(:vtr) { ['C2.Pb'] }

    context 'with unproofed user' do
      let(:user) { build(:user) }

      it 'shows unverified badge' do
        expect(rendered).to have_content(t('account.index.verification.unverified_badge'))
      end

      it 'shows warning alert instructing user to complete identity verificaton' do
        expect(rendered).to have_css('.usa-alert.usa-alert--warning')
        expect(rendered).to have_content(
          strip_tags(t('account.index.verification.finish_verifying_html', sp_name:)),
        )
        expect(rendered).to have_link(t('account.index.verification.continue_idv'), href: idv_path)
      end
    end

    context 'with non-biometric proofed user' do
      let(:user) { build(:user, :proofed) }

      it 'shows unverified badge' do
        expect(rendered).to have_content(t('account.index.verification.unverified_badge'))
      end

      it 'shows content explaining that the user needs to verify their identity again' do
        expect(rendered).to have_content(
          strip_tags(
            t(
              'account.index.verification.nonbiometric_verified_html',
              app_name: APP_NAME,
              date: @presenter.formatted_nonbiometric_idv_date,
            ),
          ),
        )
        expect(rendered).to have_content(
          strip_tags(t('account.index.verification.verify_with_biometric_html', sp_name:)),
        )
        expect(rendered).to have_link(
          t('account.index.verification.learn_more_link'),
          href: help_center_redirect_path(
            category: 'verify-your-identity',
            article: 'overview',
            flow: :account_show,
            location: :idv,
          ),
        )
      end

      it 'shows warning alert instructing user to complete identity verificaton' do
        expect(rendered).to have_css('.usa-alert.usa-alert--warning')
        expect(rendered).to have_content(
          t('account.index.verification.finish_verifying_no_sp', app_name: APP_NAME),
        )
        expect(rendered).to have_link(t('account.index.verification.continue_idv'), href: idv_path)
      end
    end

    context 'with biometric proofed user' do
      let(:user) { build(:user, :proofed_with_selfie) }

      it 'shows verified badge' do
        expect(rendered).to have_content(t('account.index.verification.verified_badge'))
      end

      it 'shows content confirming verified identity' do
        expect(rendered).to have_content(
          t('account.index.verification.you_verified_your_biometric_identity', app_name: APP_NAME),
        )
        expect(rendered).to have_link(
          t('account.index.verification.learn_more_link'),
          href: help_center_redirect_path(
            category: 'verify-your-identity',
            article: 'overview',
            flow: :account_show,
            location: :idv,
          ),
        )
      end

      it 'renders pii' do
        expect(rendered).to render_template(partial: 'accounts/_pii')
      end
    end
  end
end
