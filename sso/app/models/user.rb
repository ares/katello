# A user that can authenticate
class User
  attr_accessor :username, :password

  def initialize(username, password)
    self.username = username
    self.password = password
  end

  # authenticate user
  #
  # currently we use only Katello to authenticate user using his credentials
  # @return [true, false] was authentication successful?
  def authenticate
    auth_url = Configuration.config.backends.katello.url
    uri = URI.parse("#{auth_url}?username=#{username}&password=#{password}")
    http = Net::HTTP.new(uri.host, uri.port)
    request = Net::HTTP::Get.new(uri.request_uri)
    response = http.request(request)
    response.code == '200'
  end
end