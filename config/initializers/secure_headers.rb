SecureHeaders::Configuration.default do |config|
  config.hsts = "max-age=#{1.day.to_i}; includeSubDomains"
  config.x_frame_options = 'SAMEORIGIN'
  config.x_content_type_options = 'nosniff'
  config.x_xss_protection = '1; mode=block'
  config.x_download_options = 'noopen'
  config.x_permitted_cross_domain_policies = 'none'
  # rubocop:disable PercentStringArray
  config.csp = {
    default_src: %w('self'),
    report_only: Rails.env.development? ? true : false,
    frame_src: %w('self'), # deprecated in CSP 2.0
    child_src: %w('self'), # CSP 2.0 only; replaces frame_src
    # frame_ancestors: %w('self'), # CSP 2.0 only; overriden by x_frame_options in some browsers
    form_action: %w('self'), # CSP 2.0 only
    block_all_mixed_content: true, # CSP 2.0 only;
    connect_src: %w('self'),
    font_src: %w('self' data:),
    img_src: %w('self' data:),
    media_src: %w('self'),
    object_src: %w('none'),
    script_src: %w('self' *.newrelic.com *.nr-data.net),
    style_src: %w('self'),
    base_uri: %w('self')
  }
  # rubocop:enable PercentStringArray
  config.cookies = {
    secure: true, # mark all cookies as "Secure"
    httponly: true, # mark all cookies as "HttpOnly"
    # We need to set the SameSite setting to "Lax", not "Strict" until this bug
    # is fixed in Chrome: https://bugs.chromium.org/p/chromium/issues/detail?id=619603
    samesite: {
      lax: true # mark all cookies as SameSite=Lax.
    }
  }
  # Temporarily disabled until we configure pinning. See GitHub issue #1895.
  # config.hpkp = {
  #   report_only: false,
  #   max_age: 60.days.to_i,
  #   include_subdomains: true,
  #   pins: [
  #     { sha256: 'abc' },
  #     { sha256: '123' }
  #   ]
  # }
end

SecureHeaders::Configuration.override(:saml) do |config|
  providers = YAML.load_file("#{Rails.root}/config/service_providers.yml")
  providers = providers.fetch(Rails.env, {})
  providers.symbolize_keys!

  provider_attributes = providers[:valid_hosts].values

  acs_urls = provider_attributes.map { |hash| hash['acs_url'] }

  whitelisted_domains = acs_urls.map { |url| url.split('//')[1].split('/')[0] }

  whitelisted_domains.each { |domain| config.csp[:form_action] << domain }
end
