require 'rails_helper'

RSpec.feature 'forgot password step', :js do
  include IdvStepHelper

  it 'goes to the forgot password page from the enter password page' do
    start_idv_from_sp
    complete_idv_steps_before_enter_password_step

    click_link t('idv.forgot_password.link_text')

    expect(page).to have_current_path(idv_forgot_password_path)
  end

  it 'goes back to the enter password page from the forgot password page' do
    start_idv_from_sp
    complete_idv_steps_before_enter_password_step

    click_link t('idv.forgot_password.link_text')
    click_link t('idv.forgot_password.try_again')

    expect(page).to have_current_path(idv_enter_password_path)
  end

  it 'allows the user to reset their password' do
    start_idv_from_sp
    complete_idv_steps_before_enter_password_step

    click_link t('idv.forgot_password.link_text')
    click_button t('idv.forgot_password.reset_password')

    expect(page).to have_current_path(forgot_password_path, ignore_query: true)

    open_last_email
    click_email_link_matching(/reset_password_token/)

    expect(page).to have_current_path edit_user_password_path
  end
end
