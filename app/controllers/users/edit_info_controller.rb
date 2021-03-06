module Users
  class EditInfoController < ApplicationController
    include PhoneConfirmation

    before_action :confirm_two_factor_authenticated

    def email
      @update_form = UpdateUserEmailForm.new(current_user)
      handle_request
    end

    def mobile
      @update_form = UpdateUserMobileForm.new(current_user)
      handle_request
    end

    private

    def handle_request
      if request.put?
        attempt_submit
      else
        render
      end
    end

    def attempt_submit
      if @update_form.submit(user_params)
        process_successful_update(current_user)
      else
        render
      end
    end

    def user_params
      form = @update_form.class.name.underscore.to_sym
      params.require(form).permit(:email, :mobile)
    end

    def process_successful_update(resource)
      process_updates(resource)
      bypass_sign_in resource
    end

    def process_updates(resource)
      updater = UserFlashUpdater.new(@update_form, flash)
      updater.set_flash_message

      if @update_form.mobile_changed?
        prompt_to_confirm_mobile(@update_form.mobile)
      elsif is_flashing_format?
        EmailNotifier.new(resource).send_password_changed_email
        redirect_to profile_url
      end
    end
  end
end
