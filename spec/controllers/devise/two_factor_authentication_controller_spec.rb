require 'rails_helper'

describe Devise::TwoFactorAuthenticationController, devise: true do
  describe 'before_actions' do
    it 'includes the appropriate before_actions' do
      expect(subject).to have_actions(
        :before,
        :authenticate_scope!,
        :verify_user_is_not_second_factor_locked,
        :handle_two_factor_authentication,
        :check_already_authenticated
      )
    end
  end

  describe '#check_already_authenticated' do
    controller do
      before_action :check_already_authenticated

      def index
        render text: 'Hello'
      end
    end

    context 'when the user is fully authenticated' do
      let(:user) { create(:user, :signed_up) }

      before do
        sign_in user
      end

      it 'redirects to the profile' do
        get :index

        expect(response).to redirect_to(profile_url)
      end
    end

    context 'when the user is not fully signed in' do
      before do
        sign_in_before_2fa
      end

      it 'does not redirect to the profile' do
        get :index

        expect(response).not_to redirect_to(profile_url)
        expect(response.code).to eq('200')
      end
    end
  end

  describe '#update' do
    context 'when the user enters an invalid OTP' do
      before do
        sign_in_before_2fa

        stub_analytics(subject.current_user)
        expect(@analytics).to receive(:track_event).with('User entered invalid 2FA code')
        expect(@analytics).to receive(:track_pageview)

        expect(subject.current_user.reload.second_factor_attempts_count).to eq 0
        expect(subject.current_user).to receive(:authenticate_otp).and_return(false)
        patch :update, code: '12345'
      end

      it 'increments second_factor_attempts_count' do
        expect(subject.current_user.reload.second_factor_attempts_count).to eq 1
      end

      it 're-renders the OTP entry screen' do
        expect(response).to render_template(:show)
      end

      it 'displays flash error message' do
        expect(flash[:error]).to eq t('devise.two_factor_authentication.attempt_failed')
      end
    end

    context 'when the user enters a valid OTP' do
      before do
        sign_in_before_2fa
        expect(subject.current_user).to receive(:authenticate_otp).and_return(true)
        expect(subject.current_user.reload.second_factor_attempts_count).to eq 0
      end

      it 'redirects to the profile' do
        patch :update, code: subject.current_user.reload.direct_otp

        expect(response).to redirect_to profile_path
      end

      it 'resets the second_factor_attempts_count' do
        subject.current_user.update(second_factor_attempts_count: 1)
        patch :update, code: subject.current_user.reload.direct_otp

        expect(subject.current_user.reload.second_factor_attempts_count).to eq 0
      end

      it 'tracks the valid authentication event' do
        stub_analytics(subject.current_user)
        expect(@analytics).to receive(:track_event).with('User 2FA successful')
        expect(@analytics).to receive(:track_event).with('Authentication Successful')

        patch :update, code: subject.current_user.reload.direct_otp
      end
    end

    context 'when user has not changed their number' do
      it 'does not perform SmsSenderNumberChangeJob' do
        user = create(:user, :signed_up)
        sign_in user

        expect(SmsSenderNumberChangeJob).to_not receive(:perform_later).with(user)

        patch :update, code: user.direct_otp
      end
    end

    context 'when the user is TOTP enabled' do
      before do
        sign_in_before_2fa
        @secret = subject.current_user.generate_totp_secret
        subject.current_user.otp_secret_key = @secret
      end

      context 'when the user enters a valid TOTP' do
        before do
          patch :update, code: generate_totp_code(@secret)
        end

        it 'redirects to the profile' do
          expect(response).to redirect_to profile_path
        end
      end

      context 'when the user enters an invalid TOTP' do
        before do
          patch :update, code: 'abc'
        end

        it 'increments second_factor_attempts_count' do
          expect(subject.current_user.reload.second_factor_attempts_count).to eq 1
        end

        it 're-renders the TOTP entry screen' do
          expect(response).to render_template(:show_totp)
        end

        it 'displays flash error message' do
          expect(flash[:error]).to eq t('devise.two_factor_authentication.attempt_failed')
        end
      end

      context 'user requests a direct OTP via SMS and enters the direct OTP' do
        before do
          get :new, sms: true
          patch :update, code: subject.current_user.direct_otp
        end

        it 'redirects to the profile' do
          expect(response).to redirect_to profile_path
        end
      end
    end

    context 'when the user lockout period expires' do
      before do
        sign_in_before_2fa
        subject.current_user.update(
          second_factor_locked_at: Time.zone.now - Devise.direct_otp_valid_for - 1.seconds,
          second_factor_attempts_count: 3
        )
      end

      describe 'when user submits an invalid OTP' do
        before do
          patch :update, code: '12345'
        end

        it 'resets attempts count' do
          expect(subject.current_user.reload.second_factor_attempts_count).to eq 1
        end

        it 'resets second_factor_locked_at' do
          expect(subject.current_user.reload.second_factor_locked_at).to eq nil
        end
      end

      describe 'when user submits a valid OTP' do
        before do
          patch :update, code: subject.current_user.direct_otp
        end

        it 'resets attempts count' do
          expect(subject.current_user.reload.second_factor_attempts_count).to eq 0
        end

        it 'resets second_factor_locked_at' do
          expect(subject.current_user.reload.second_factor_locked_at).to eq nil
        end
      end
    end
  end

  describe '#show' do
    context 'when resource is not fully authenticated yet' do
      before do
        sign_in_before_2fa
      end

      it 'renders the :show view' do
        get :show
        expect(response).to_not be_redirect
        expect(response).to render_template(:show)
      end

      it 'tracks the pageview' do
        stub_analytics(subject.current_user)
        expect(@analytics).to receive(:track_pageview)

        get :show
      end

      context 'when user is TOTP enabled' do
        before do
          allow(subject.current_user).to receive(:totp_enabled?).and_return(true)
        end

        it 'renders the :show_totp view' do
          get :show
          expect(response).to_not be_redirect
          expect(response).to render_template(:show_totp)
        end

        it 'renders the :show view if method=sms' do
          get :show, method: 'sms'
          expect(response).to_not be_redirect
          expect(response).to render_template(:show)
        end
      end

      context 'when FeatureManagement.prefill_otp_codes? is true' do
        it 'sets @code_value to correct OTP value' do
          allow(FeatureManagement).to receive(:prefill_otp_codes?).and_return(true)
          get :show

          expect(assigns(:code_value)).to eq(subject.current_user.direct_otp)
        end
      end

      context 'when FeatureManagement.prefill_otp_codes? is false' do
        it 'does not set @code_value' do
          allow(FeatureManagement).to receive(:prefill_otp_codes?).and_return(false)
          get :show

          expect(assigns(:code_value)).to be_nil
        end
      end
    end
  end

  describe '#new' do
    before do
      sign_in_before_2fa
    end

    it 'redirects to :show' do
      get :new

      expect(response).to redirect_to(action: :show, method: 'sms')
    end

    it 'sends a new OTP' do
      old_otp = subject.current_user.direct_otp
      allow(SmsSenderOtpJob).to receive(:perform_later)
      get :new

      expect(SmsSenderOtpJob).to have_received(:perform_later).
        with(subject.current_user.direct_otp, subject.current_user.mobile)
      expect(subject.current_user.direct_otp).not_to eq(old_otp)
      expect(subject.current_user.direct_otp).not_to be_nil
    end

    it 'tracks the event' do
      stub_analytics(subject.current_user)
      expect(@analytics).to receive(:track_event).with('User requested a new OTP code')

      get :new
    end
  end
end
