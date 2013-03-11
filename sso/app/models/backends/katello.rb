require 'net/http'
require 'net/https'

class Backends::Katello < Backends::Base
  attr_accessor :username, :password, :auth_url, :response

  def authenticate(opts)
    parse_options(opts)
    do_auth
    check_result
  end

  private

  def parse_options(opts)
    @username = opts[:username]
    @password = opts[:password]
    @auth_url = Configuration.config.backends.katello.url
  end

  def do_auth
    uri       = URI.parse("#{auth_url}?username=#{username}&password=#{password}")
    http      = Net::HTTP.new(uri.host, uri.port)
    request   = Net::HTTP::Get.new(uri.request_uri)
    @response = http.request(request)
  rescue Timeout::Error, Errno::EINVAL, Errno::ECONNRESET, EOFError, Net::HTTPBadResponse,
      Net::HTTPHeaderSyntaxError, Net::ProtocolError, Errno::ECONNREFUSED => e
    Rails.logger.error "And error #{e.class} occured with message #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    # @response will be nil and will result in false
  end

  def check_result
    @response && @response.code == '200'
  end
end