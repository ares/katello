require 'pathname'
require "openid"
require "openid/consumer/discovery"
require 'openid/store/filesystem'


class LoginController < ApplicationController
  include OpenID::Server
  layout nil

  def index
    if session[:username] && cookies[:username].blank?
      cookies[:username] = session[:username]
      redirect_to params[:return_url] || root_path
    else
      session[:return_url] = params[:return_url]
    end
  end

  def login
    credentials = params[:user] || {}
    user        = User.new(credentials[:username], credentials[:password])
    if user.authenticate
      session[:username] = user.username
      cookies[:username] = { :value => session[:username], :expires => 10.hours.from_now }
      redirect_to session[:return_url] || root_path
    else
      flash.now[:error] = 'Authentication failed, try again'
      render :action => 'index'
    end
  end

  def provider
    begin
      oidreq = server.decode_request(params)
    rescue ProtocolError => e
      # invalid openid request, so just display a page with an error message
      render :text => e.to_s, :status => 500
      return
    end

    # no openid.mode was given
    unless oidreq
      render :text => "This is an OpenID server endpoint."
      return
    end

    # cookie was set but no user is logged in, we need to identify user first so send him to index
    if request.get? && session[:username].blank?
      redirect_to root_path(:return_url => params[:"openid.return_to"])
      return
    end

    # casual OpenID authentication request
    if oidreq.kind_of?(CheckIDRequest)

      identity = oidreq.identity

      if is_authorized(identity, oidreq.trust_root)
        req_identity = identity.split('/').last

        if session[:username] != req_identity
          # cookie says identifies another that current user, current user has precedence
          # we reset cookie and let the process begin again from RP
          cookies[:username] = session[:username]
          redirect_to params[:"openid.return_to"]
          return
        else
          # we make sure cookie is set and response to OpenID auth request
          cookies[:username] = { :value => session[:username], :expires => 10.hours.from_now }
          oidresp            = oidreq.answer(true, nil, identity)
        end
      end
    else
      oidresp = server.handle_request(oidreq)
    end

    render_response(oidresp)
  end

  def logout
    session[:username] = nil
    redirect_to root_path
  end

  private

  def is_authorized(*args)
    true # TODO whitelist
  end

  def render_response(oidresp)
    if oidresp.needs_signing
      signed_response = server.signatory.sign(oidresp)
    end
    web_response = server.encode_response(oidresp)

    case web_response.code
      when HTTP_OK
        render :text => web_response.body, :status => 200

      when HTTP_REDIRECT
        redirect_to web_response.headers['location']

      else
        render :text => web_response.body, :status => 400
    end
  end

  def url_for_user
    url_for :controller => 'user', :action => session[:username]
  end

  def server
    if @server.nil?
      server_url = url_for :controller => 'login', :action => 'provider', :only_path => false
      dir        = Pathname.new(Rails.root).join('db').join('openid-store')
      store      = OpenID::Store::Filesystem.new(dir)
      @server    = Server.new(store, server_url)
    end
    return @server
  end
end