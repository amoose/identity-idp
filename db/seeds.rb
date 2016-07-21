# enable registrations by default
AppSetting.find_or_create_by!(name: 'RegistrationsEnabled') do |setting|
  setting.value = '1'
end

if Rails.env.development?
  # Create a few dummy accounts for use during development.  These accounts all
  # have 'password' as password and are setup for mobile OTP delivery.
  %w(test1@test.com test2@test.com).each_with_index do |email, index|
    User.find_or_create_by!(email: email) do |user|
      user.uuid = format('testuuid-3511-40a3-a0fc-ee64cbd896%02d', index)
      user.skip_confirmation!
      user.reset_password('password', 'password')
      user.mobile = format('+1 (415) 555-01%02d', index)
      user.mobile_confirmed_at = Time.current
      Event.create(
        user_id: user.id,
        event_type: :account_created,
        user_agent: 'Chrome 99',
        ip_address: '127.0.0.1'
      )
    end
  end
end
