require 'oauth/request_proxy/rack_request'

require 'openid/store/filesystem'
require 'rack/openid'
openid_store_path = Pathname.new(Rails.root).join('db').join('openid-store')
Rails.configuration.middleware.use Rack::OpenID, OpenID::Store::Filesystem.new(openid_store_path)

Rails.configuration.middleware.use RailsWarden::Manager do |config|
  config.failure_app = FailedAuthenticationController
  config.default_scope = :user

  # all UI requests are handled in the default scope
  config.scope_defaults(
    :user,
    :strategies   => [:openid, Katello.config.warden.to_sym],
    :store        => true,
    :action       => 'unauthenticated_ui'
  )

  # API requests are handled in the :api scope
  config.scope_defaults(
    :api,
    :strategies   => [:oauth, :certificate, Katello.config.warden.to_sym, :no_credentials],
    :store        => false,
    :action       => 'unauthenticated_api'
  )

  # request from SSO application to authenticate user
  config.scope_defaults(
      :sso,
      :strategies => [Katello.config.warden.to_sym],
      :store      => false,
      :action     => 'unauthenticated_sso'
  )
end

class Warden::SessionSerializer
  def serialize(user)
    raise ArgumentError, "Cannot serialize invalid user object: #{user}" if not user.is_a? User and user.id.is_a? Integer
    user.id
  end

  def deserialize(id)
    raise ArgumentError, "Cannot deserialize non-integer id: #{id}" unless id.is_a? Integer
    User.find(id) rescue nil
  end
end

Warden::Manager.after_authentication do |user,auth,opts|
  user = user.username if user.respond_to? :username
  message = auth.winning_strategy.message
  Rails.logger.debug "User #{user} authenticated: #{auth.winning_strategy.message}"
end

# authenticate against OpenID
Warden::Strategies.add(:openid) do
  def valid?
    # if user supplies password we don't want to make OpenID auth request
    Katello.config.sso.enable && params[:password].blank?
  end

  def authenticate!
    if (response = env[Rack::OpenID::RESPONSE])
      # we have response from OpenID provider so we try to login user
      case response.status
        when :success
          if (user = User.find_by_username(response.identity_url.split('/').last))
            success!(user)
          else
            message = 'User not found'
            Rails.logger.warn(message) && fail(message)
            throw(:warden, :openid => { :response => response }) unless params[:sso_tried].present?
          end
        else
          # :missing status means that request was not made, probably wrong certificate on Signo side
          message = response.respond_to?(:message) ? response.message : "OpenID authentication failed: #{response.status}"
          Rails.logger.error(message) && fail(message)
          throw(:warden, :openid => { :response => response }) unless params[:sso_tried].present?
      end
    elsif (username = cookies[:username] || params[:username])
      # we already have cookie
      identifier = "#{Katello.config.sso.provider_url}/user/#{username}"
      custom!([401,
               { 'WWW-Authenticate' => Rack::OpenID.build_header({:identifier => identifier}) },
               ''])
    else
      # we have no cookie yet so we plain redirect to OpenID provider to login
      redirect!("#{Katello.config.sso.provider_url}?return_url=#{request.url}")
    end
  end
end

# authenticate against database
Warden::Strategies.add(:database) do

  # relevant only when username and password params are set
  def valid?
    (params[:username] && params[:password]) or (params[:auth_username] && params[:auth_password])
  end

  def authenticate!
    if params[:auth_username] && params[:auth_password]
      username, password = params[:auth_username], params[:auth_password] # API simple auth
    elsif params[:username] && params[:password]
      username, password = params[:username], params[:password] # UI form
    end

    Rails.logger.debug("Warden is authenticating #{params[:auth_username]} against database")
    user = User.authenticate!(username, password)

    user ? success!(user, "database") : fail!("Username or password do not match database - could not log in")
  end
end

# authenticate against LDAP
Warden::Strategies.add(:ldap) do

  # relevant only when username and password params are set
  def valid?
    (params[:username] && params[:password]) or (params[:auth_username] && params[:auth_password])
  end

  def authenticate!
    if params[:auth_username] && params[:auth_password]
      username, password = params[:auth_username], params[:auth_password] # API simple auth
    elsif params[:username] && params[:password]
      username, password = params[:username], params[:password] # UI form
    end

    Rails.logger.debug("Warden is authenticating #{params[:username]} against ldap")
    user = User.authenticate_using_ldap!(username, password)

    user ? success!(user, "LDAP") : fail!("Could not log in using LDAP")
  end
end

Warden::Strategies.add(:certificate) do

  def valid?
    true
  end

  def authenticate!
    ssl_client_cert = client_cert_from_request
    return fail('No ssl client certificate, skipping ssl-certificate authentication') if ssl_client_cert.blank?
    consumer_cert = OpenSSL::X509::Certificate.new(ssl_client_cert)
    uuid = uuid(consumer_cert)
    u = CpConsumerUser.new(:uuid =>uuid, :username =>uuid, :remote_id=> uuid)
    success!(u, "certificate")
  end

  def client_cert_from_request
    cert = request.env['SSL_CLIENT_CERT'] || request.env['HTTP_SSL_CLIENT_CERT']
    return nil if cert.blank? || cert == "(null)"
    # apache does not preserve new lines in cert file - work-around:
    if cert.include?("-----BEGIN CERTIFICATE----- ")
      cert = cert.to_s.gsub("-----BEGIN CERTIFICATE----- ","").gsub(" -----END CERTIFICATE-----","")
      cert.gsub!(" ","\n")
      cert = "-----BEGIN CERTIFICATE-----\n#{cert}-----END CERTIFICATE-----\n"
    end
    return cert
  end

  def uuid(cert)
    drop_cn_prefix_from_subject(cert.subject.to_s)
  end

  def drop_cn_prefix_from_subject(subject_string)
    subject_string.sub(/\/CN=/i, '')
  end
end

Warden::Strategies.add(:oauth) do
  def valid?
    true
  end

  # TODO test ['HTTP_KATELLO_SYSTEM'] (foreman-katello-engine)
  # TODO ask Ivan - DoS vuln fix
  #               - foreman-katello-engine key&secret configuration??
  def authenticate!
    rack_request = Rack::Request.new(request.env)
    consumer_key = OAuth::RequestProxy.proxy(rack_request).oauth_consumer_key

    # we expect system in "system_<name>" form
    if (system = request.headers['HTTP_KATELLO_SYSTEM'].split('_').first)
      return fail("no 'katello-user' header") if (user = request.headers['HTTP_KATELLO_USER']).blank?
    else
      user = consumer_key
    end

    consumers = system.present? ? [system_consumer(system)] : user_consumers(consumer_key)

    # lazily construct at least one matching signature
    result = consumers.any? do |consumer|
      signature = OAuth::Signature.build(rack_request) { [nil, consumer.secret] }
      signature.verify
    end

    return fail!("Invalid oauth signature") unless result

    u = User.where(:username => user).first
    u ? success!(u, "OAuth") : fail!("Username is not correct - could not log in")
  rescue OAuth::Signature::UnknownSignatureMethod => e
    Rails.logger.error "Unknown oauth signature method"+ e.to_s
    fail!("Unknown oauth signature method"+ e.to_s)
  rescue => e
    Rails.logger.error "exception occurred while authenticating via oauth "+ e.to_s
    fail!("exception occurred while authenticating via oauth "+ e.to_s)
  end

  def system_consumer(system)
    oauth_config = Katello.config[system]
    unless oauth_config.respond_to?(:oauth_key) && oauth_config.respond_to?(:oauth_secret)
      fail!("Missing OAuth configuration for system: '#{system}'")
    end
    return [OAuth::Consumer.new(oauth_config.oauth_key,
                                oauth_config.oauth_secret)]
  end

  def user_consumers(consumer_key)
    secrets = fetch_user_secrets(consumer_key)
    secrets.map { |s| OAuth::Consumer.new consumer_key, s, oauth_params }
  end

  def fetch_user_secrets(consumer_key)
    uri = URI.parse("https://localhost/signo/tokens/#{consumer_key}.json")
    request = Net::HTTP::Get.new(uri.path)
    consumer = OAuth::Consumer.new('katello',
                                   'shhhh',
                                   oauth_params)
    consumer.sign!(request)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    resp = http.request(request)
    JSON.parse(resp.body).reverse
  rescue JSON::ParserError => e
    logger.debug "User secrets could not be fetched, response parsing error - #{e.message}"
    return []
  end

  def oauth_params
    { :site => 'https://localhost/',
      :http_method => 'get',
      :request_token_path => "",
      :authorize_path => "",
      :access_token_path => "" }
  end
end

Warden::Strategies.add(:no_credentials) do
  def valid?
    true
  end

  def authenticate!
    custom! [401, {"WWW-Authenticate" => 'Basic realm="Secure Area"'}, ["No Credentials provided"]]
  end
end
