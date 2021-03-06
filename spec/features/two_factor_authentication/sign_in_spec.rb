require 'rails_helper'

include Features::ActiveJobHelper

#   As a user
#   I want to sign in
#   So I can visit protected areas of the site
feature 'Two Factor Authentication' do
  describe 'When the user has not setup 2FA' do
    scenario 'user is prompted to setup two factor authentication at first sign in' do
      sign_in_before_2fa

      expect(current_path).to eq phone_setup_path
      expect(page).
        to have_content t('devise.two_factor_authentication.two_factor_setup')
    end

    scenario 'user does not fill out a mobile number when signing up' do
      sign_up_and_set_password
      click_button 'Submit'

      expect(current_path).to eq phone_setup_path
    end

    scenario 'user attempts to circumnavigate OTP setup' do
      sign_in_before_2fa

      visit edit_user_registration_path

      expect(current_path).to eq phone_setup_path
    end

    describe 'user selects Mobile' do
      scenario 'user leaves mobile blank' do
        sign_in_before_2fa
        fill_in 'Mobile', with: ''
        click_button 'Submit'

        expect(page).to have_content invalid_mobile_message
      end

      scenario 'user enters an invalid number with no digits' do
        sign_in_before_2fa
        fill_in 'Mobile', with: 'five one zero five five five four three two one'
        click_button 'Submit'

        expect(page).to have_content invalid_mobile_message
      end

      scenario 'user enters a valid number' do
        user = sign_in_before_2fa
        fill_in 'Mobile', with: '555-555-1212'
        click_button 'Submit'

        expect(page).to_not have_content invalid_mobile_message
        expect(current_path).to eq phone_confirmation_path
        expect(user.reload.mobile).to_not eq '+1 (555) 555-1212'
      end
    end
  end # describe 'When the user has not set a preferred method'

  describe 'When the user has set a preferred method' do
    describe 'Using Mobile' do
      # Scenario: User with mobile 2fa is prompted for otp
      #   Given I exist as a user
      #   And I am not signed in and have mobile 2fa enabled
      #   When I sign in
      #   Then an OTP is sent to my mobile
      #   And I am prompted to enter it
      context 'user is prompted for otp via mobile only', sms: true do
        before do
          reset_job_queues
          @user = create(:user, :signed_up)
          reset_email
          sign_in_before_2fa(@user)
        end

        it 'lets the user know they are signed in' do
          expect(page).to have_content t('devise.sessions.signed_in')
        end

        it 'asks the user to enter an OTP' do
          expect(page).
            to have_content t('devise.two_factor_authentication.header_text')
        end

        it 'does not send an OTP via email' do
          expect(last_email).to_not have_content('one-time password')
        end

        it 'does not allow user to bypass entering OTP' do
          visit edit_user_registration_path

          expect(current_path).to eq user_two_factor_authentication_path
        end

        it 'displays an error message if the code field is empty', js: true do
          fill_in 'code', with: ''
          click_button 'Submit'

          expect(page).to have_content('Please fill in all required fields')
        end
      end
    end

    scenario 'user can resend one-time password (OTP)' do
      user = create(:user, :signed_up)
      sign_in_before_2fa(user)
      click_link 'request a new one'

      expect(page).to have_content t('devise.two_factor_authentication.user.new_otp_sent')
    end

    scenario 'user who enters OTP incorrectly 3 times is locked out for OTP validity period' do
      user = create(:user, :signed_up)
      sign_in_before_2fa(user)

      stub_analytics(user)
      expect(@analytics).to receive(:track_pageview).exactly(3).times
      expect(@analytics).to receive(:track_event).exactly(3).times.
        with('User entered invalid 2FA code')
      expect(@analytics).to receive(:track_event).with('User reached max 2FA attempts')

      3.times do
        fill_in('code', with: 'bad-code')
        click_button('Submit')
      end

      expect(page).to have_content t('titles.account_locked')

      # let 10 minutes (otp validity period) magically pass
      user.update(second_factor_locked_at: Time.zone.now - (Devise.direct_otp_valid_for + 1.second))

      sign_in_before_2fa(user)

      expect(page).to have_content t('devise.two_factor_authentication.header_text')
    end

    context 'user signs in while locked out' do
      it 'signs the user out and lets them know they are locked out' do
        user = create(:user, :signed_up)
        user.update(second_factor_locked_at: Time.zone.now - 1.minute)
        allow_any_instance_of(User).to receive(:max_login_attempts?).and_return(true)
        sign_in_before_2fa(user)

        expect(page).to have_content 'Your account is temporarily locked'

        visit edit_user_registration_path
        expect(current_path).to eq root_path
      end
    end
  end # describe 'When the user has set a preferred method'
end # feature 'Two Factor Authentication'
