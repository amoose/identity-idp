class Event < ActiveRecord::Base
  belongs_to :user

  enum event_type: {
    account_created: 1,
    phone_confirmed: 2,
    password_changed: 3,
    phone_changed: 4,
    email_changed: 5
  }

  validates :event_type, presence: true
  validates :ip_address, presence: true

  def self.event_type_to_s(event_type)
    raise 'Invalid event type' unless event_types.keys.include?(event_type)
    I18n.t('event_types.' + event_type.to_s)
  end
end
