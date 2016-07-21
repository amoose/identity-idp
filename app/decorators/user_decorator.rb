include ActionView::Helpers::DateHelper

UserDecorator = Struct.new(:user) do
  def lockout_time_remaining
    (Devise.direct_otp_valid_for - (Time.zone.now - user.second_factor_locked_at)).to_i
  end

  def lockout_time_remaining_in_words
    distance_of_time_in_words(
      Time.zone.now, Time.zone.now + lockout_time_remaining, true, highest_measures: 2
    )
  end

  def confirmation_period_expired_error
    I18n.t('errors.messages.confirmation_period_expired', period: confirmation_period)
  end

  def confirmation_period
    distance_of_time_in_words(
      Time.zone.now, Time.zone.now + Devise.confirm_within, true, accumulate_on: :hours
    )
  end

  def first_sentence_for_confirmation_email
    if user.reset_requested_at
      "Your #{APP_NAME} account has been reset by a tech support representative. " \
      "In order to continue, you must confirm your email address."
    else
      "To #{user.confirmed_at ? 'finish updating' : 'continue creating'} your " \
      "#{APP_NAME} Account, you must confirm your email address."
    end
  end

  def may_bypass_2fa?(session = {})
    omniauthed?(session)
  end

  def masked_two_factor_phone_number
    masked_number(user.mobile)
  end

  def identity_not_verified?
    !user.verified?
  end

  def qrcode(otp_secret_key)
    options = {
      issuer: 'Login.gov',
      otp_secret_key: otp_secret_key
    }
    url = user.provisioning_uri(nil, options)
    qrcode = RQRCode::QRCode.new(url)
    qrcode.as_png(size: 300).to_data_url
  end

  def blocked_from_entering_2fa_code?
    user.second_factor_locked_at && !blocked_from_2fa_period_expired?
  end

  def no_longer_blocked_from_entering_2fa_code?
    user.second_factor_locked_at && blocked_from_2fa_period_expired?
  end

  private

  def omniauthed?(session)
    return false if session[:omniauthed] != true

    session.delete(:omniauthed)
  end

  def masked_number(number)
    "***-***-#{number[-4..-1]}"
  end

  def blocked_from_2fa_period_expired?
    (Time.current - user.second_factor_locked_at) > Devise.direct_otp_valid_for
  end
end
