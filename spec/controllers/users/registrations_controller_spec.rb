require 'rails_helper'

include Features::MailerHelper
include Features::LocalizationHelper
include Features::ActiveJobHelper

describe Users::RegistrationsController, devise: true do
  describe '#update' do
    let(:user) { create(:user, :signed_up, email: 'old_email@example.com') }
    let(:second_user) do
      create(:user, :signed_up, email: 'mobile@example.com', mobile: '+1 (202) 555-1213')
    end
    let(:new_email) { 'new_email@example.com' }
    let!(:old_encrypted_password) { user.encrypted_password }

    let(:attrs_with_already_taken_mobile) do
      {
        email: user.email,
        mobile: second_user.mobile,
        current_password: '!1aZ' * 32,
        password: ''
      }
    end

    let(:attrs_with_new_email_and_mobile) do
      {
        email: new_email,
        mobile: '555-555-5555',
        current_password: '!1aZ' * 32,
        password: ''
      }
    end

    let(:attrs_for_new_mobile) do
      {
        email: second_user.email,
        mobile: '555-555-5555',
        current_password: '!1aZ' * 32,
        password: ''
      }
    end

    let(:attrs_with_blank_mobile) do
      {
        email: second_user.email,
        mobile: '',
        current_password: '!1aZ' * 32,
        password: ''
      }
    end

    let(:attrs_with_mobile) do
      {
        email: second_user.email,
        mobile: second_user.mobile,
        current_password: '!1aZ' * 32,
        password: ''
      }
    end

    let(:attrs_with_new_email) do
      {
        email: new_email,
        mobile: user.mobile,
        current_password: '!1aZ' * 32,
        password: ''
      }
    end

    let(:attrs_without_current_password) do
      {
        email: user.email,
        mobile: second_user.mobile,
        current_password: '',
        password: ''
      }
    end

    let(:attrs_with_invalid_current_password) do
      {
        email: user.email,
        mobile: user.mobile,
        current_password: 'foo',
        password: ''
      }
    end

    let(:attrs_with_blank_email) do
      {
        email: '',
        mobile: user.mobile,
        current_password: '!1aZ' * 32,
        password: ''
      }
    end

    let(:attrs_with_new_valid_password) do
      {
        email: user.email,
        mobile: user.mobile,
        current_password: '!1aZ' * 32,
        password: '@Aaaaaa1'
      }
    end

    let(:attrs_with_new_invalid_password) do
      {
        email: user.email,
        mobile: user.mobile,
        current_password: '!1aZ' * 32,
        password: '123'
      }
    end

    let(:attrs_with_blank_new_password) do
      {
        email: user.email,
        mobile: user.mobile,
        current_password: '!1aZ' * 32,
        password: ''
      }
    end

    shared_examples 'adding_mobile' do
      it 'redirects to phone confirmation page with message', sms: true do
        expect(flash[:notice]).
          to eq t('devise.registrations.mobile_update_needs_confirmation')

        expect(response).to redirect_to phone_confirmation_send_path

        expect(user.reload.mobile).to_not eq '+1 (555) 555-5555'

        expect(enqueued_jobs.size).to eq 1
      end
    end

    shared_examples 'updating_profile' do
      it 'redirects to user edit page with flash notice' do
        expect(response).to redirect_to(edit_user_registration_path)

        expect(flash[:notice]).to eq t('devise.registrations.updated')
      end
    end

    shared_examples 'updating_mobile' do
      it 'redirects to phone confirmation page with success message' do
        expect(response).to redirect_to(phone_confirmation_send_path)

        expect(flash[:notice]).to eq t('devise.registrations.mobile_update_needs_confirmation')

        expect(test_user.reload.mobile).to_not eq '+1 (555) 555-5555'
      end
    end

    shared_examples 'updating_both_email_and_mobile' do
      it 'redirects to phone confirmation page with success message' do
        expect(response).to redirect_to(phone_confirmation_send_path)

        expect(flash[:notice]).
          to eq t('devise.registrations.email_and_mobile_need_confirmation')

        expect(test_user.reload.mobile).to_not eq '+1 (555) 555-5555'
      end
    end

    context 'user updates existing mobile number' do
      before do
        sign_in(second_user)
        reset_job_queues
        patch :update, update_user_profile_form: attrs_for_new_mobile
      end

      it_behaves_like 'updating_mobile' do
        let(:test_user) { second_user }
      end

      it 'allows the user to abandon confirmation' do
        get :edit

        expect(response).to render_template(:edit)
      end
    end

    it 'tracks the phone number update event' do
      sign_in(second_user)

      stub_analytics(second_user)
      expect(@analytics).to receive(:track_event).
        with('User asked to update their phone number')

      patch :update, update_user_profile_form: attrs_for_new_mobile
    end

    # Scenario: User updates both email and number
    #   Given I am signed in and editing my profile
    #   When I update both my mobile and email
    #   Then I am asked to confirm both my email and mobile
    #   But OTP confirmation only goes to phone
    context 'user updates both email and mobile number' do
      before do
        sign_in(user)
        reset_email
        put :update, update_user_profile_form: attrs_with_new_email_and_mobile
      end

      it_behaves_like 'updating_both_email_and_mobile' do
        let(:test_user) { user }
      end

      it 'requires the user to confirm both their new email and mobile' do
        expect(flash[:notice]).to eq t('devise.registrations.email_and_mobile_need_confirmation')
        expect(last_email.body).to_not include 'one-time password'
        expect(user.reload.email).to_not eq 'new_email@example.com'
      end
    end

    # Scenario: User deletes phone number
    #   Given I am signed in and editing my profile
    #   When I try to remove my mobile number
    #   Then I see an invalid number message
    context 'user attempts to remove mobile number' do
      render_views

      it 'displays error message and does not remove mobile' do
        sign_in(second_user)
        put :update, update_user_profile_form: attrs_with_blank_mobile

        expect(response.body).to have_content invalid_mobile_message
        expect(second_user.reload.mobile).to be_present
      end
    end

    # Scenario: User attempts to delete email
    #   Given I am signed in and editing my profile
    #   When I remove my email
    #   Then I see an error message
    context 'user removes email address' do
      render_views

      it 'displays an error message and does not delete the email' do
        sign_in(user)
        put :update, update_user_profile_form: attrs_with_blank_email

        expect(response.body).to have_content invalid_email_message
        expect(user.reload.email).to be_present
      end
    end

    context 'user changes email' do
      before do
        sign_in(user)
        put :update, update_user_profile_form: attrs_with_new_email
      end

      it 'lets user know they need to confirm their new email' do
        expect(response).to redirect_to edit_user_registration_url
        expect(flash[:notice]).to eq t('devise.registrations.email_update_needs_confirmation')
        expect(response).to render_template('devise/mailer/confirmation_instructions')
        expect(user.reload.email).to eq 'old_email@example.com'
      end
    end

    context "user changes email to another user's email address" do
      it 'lets user know they need to confirm their new email' do
        sign_in(user)
        put :update, update_user_profile_form: attrs_with_new_email.merge(email: second_user.email)

        expect(response).to redirect_to edit_user_registration_url
        expect(flash[:notice]).to eq t('devise.registrations.email_update_needs_confirmation')
        expect(response).to render_template('user_mailer/signup_with_your_email')
        expect(user.reload.email).to eq 'old_email@example.com'
        expect(last_email.subject).to eq t('mailer.email_reuse_notice.subject')
      end
    end

    context 'user changes password', email: true do
      before do
        sign_in(user)
        put :update, update_user_profile_form: attrs_with_new_valid_password
      end

      it_behaves_like 'updating_profile'

      it 'changes the password successfully and sends the user an email' do
        expect(user.reload.encrypted_password).to_not eq old_encrypted_password
        expect(response).to render_template('user_mailer/password_changed')
      end
    end

    describe 'EmailNotifier' do
      context 'user changes password', email: true do
        it 'calls EmailNotifier' do
          notifier = instance_double(EmailNotifier)

          expect(EmailNotifier).to receive(:new).with(user).and_return(notifier)
          expect(notifier).to receive(:send_password_changed_email)

          sign_in(user)
          put :update, update_user_profile_form: attrs_with_new_valid_password
        end
      end
    end

    context 'invalid password' do
      render_views

      it 'displays invalid password error' do
        sign_in(user)
        put :update, update_user_profile_form: attrs_with_new_invalid_password

        expect(response.body).to have_content('too short')
        expect(user.reload.encrypted_password).to eq old_encrypted_password
      end
    end

    context "user updates profile with another user's mobile but without current password" do
      render_views

      it 'displays error about blank current password but not about mobile' do
        sign_in(user)
        put(
          :update,
          update_user_profile_form: attrs_without_current_password.merge(mobile: second_user.mobile)
        )

        expect(response.body).to have_content("can't be blank")
        expect(response.body).to_not have_content('has already been taken')
        expect(user.reload.email).to eq 'old_email@example.com'
      end
    end

    context "user updates profile with invalid email and another user's mobile", sms: true do
      render_views

      it 'displays error about invalid email and does not send any SMS', sms: true do
        sign_in(user)
        put(
          :update,
          update_user_profile_form: attrs_with_already_taken_mobile.merge!(email: 'foo')
        )

        expect(response.body).to have_content('Please enter a valid email')
        expect(response.body).to_not have_content('has already been taken')
        expect(enqueued_jobs).to eq []
        expect(performed_jobs).to eq []
      end
    end

    context "user updates profile with invalid mobile and another user's email" do
      render_views

      it 'displays error about invalid email', email: true do
        sign_in(user)
        put(
          :update,
          update_user_profile_form: attrs_with_already_taken_mobile.merge!(
            email: second_user.email, mobile: '703'
          )
        )

        expect(flash).to be_empty
        expect(response.body).to have_content('number is invalid')
        expect(response.body).to_not have_content('has already been taken')
        expect(last_email).to be_nil
      end
    end

    context 'blank new password' do
      render_views

      it 'does not change password' do
        sign_in(user)
        put :update, update_user_profile_form: attrs_with_blank_new_password

        expect(user.reload.encrypted_password).to eq old_encrypted_password
        expect(response).to redirect_to edit_user_registration_url
      end
    end

    context 'invalid current password' do
      render_views

      it 'displays invalid password error' do
        sign_in(user)
        put :update, update_user_profile_form: attrs_with_invalid_current_password

        expect(response.body).to have_content('is invalid')
      end
    end
  end

  describe '#new' do
    it 'triggers completion of "demo" experiment' do
      expect(subject).to receive(:ab_finished).with(:demo)
      get :new
    end

    it 'tracks the pageview' do
      stub_analytics
      expect(@analytics).to receive(:track_pageview)

      get :new
    end
  end

  describe '#create' do
    it 'tracks successful user registration' do
      stub_analytics

      form = instance_double(RegisterUserEmailForm)
      allow(RegisterUserEmailForm).to receive(:new).and_return(form)
      allow(form).to receive(:submit).with(email: 'new@example.com').and_return(true)
      allow(form).to receive(:email_taken?).and_return(false)
      allow(form).to receive_message_chain(:user, :email).and_return('new@example.com')

      expect(@analytics).to receive(:track_event).with('Account Created', form.user)
      expect(subject).to receive(:create_event).with(:account_created, form.user)

      post :create, user: { email: 'new@example.com' }
    end

    it 'tracks successful user registration with existing email' do
      existing_user = create(:user)

      stub_analytics

      form = instance_double(RegisterUserEmailForm)
      allow(RegisterUserEmailForm).to receive(:new).and_return(form)
      allow(form).to receive(:submit).with(email: existing_user.email).and_return(true)
      allow(form).to receive(:email_taken?).and_return(true)
      allow(form).to receive(:email).and_return(existing_user.email)
      allow(form).to receive_message_chain(:user, :email).and_return(existing_user.email)

      expect(@analytics).to receive(:track_event).
        with('Registration Attempt with existing email', existing_user)

      post :create, user: { email: existing_user.email }
    end

    it 'tracks unsuccessful user registration' do
      stub_analytics

      expect(@analytics).to receive(:track_anonymous_event).
        with('User Registration: invalid email', 'invalid@')

      post :create, user: { email: 'invalid@' }
    end
  end

  describe '#start' do
    it 'tracks the pageview' do
      stub_analytics
      expect(@analytics).to receive(:track_pageview)

      get :start
    end
  end

  describe '#edit' do
    it 'tracks the pageview' do
      user = create(:user, :signed_up)
      sign_in(user)

      stub_analytics(subject.current_user)
      expect(@analytics).to receive(:track_pageview)

      get :edit
    end
  end
end
