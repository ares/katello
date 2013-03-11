require 'test_helper'

describe LoginController do
  let(:username) { 'admin' }
  let(:password) { 'admin' }

  describe "#index" do

    context "no return_url parameter" do
      before { get :index }
      it { response.must_be :success? }
    end

    context "return_url set" do
      let(:url) { 'http://localhost:3001' }
      before { get :index, :return_url => url }

      it "should store url to session" do
        session[:return_url].must_equal(url)
      end
    end
  end

  describe "#login" do
    context "auth successful" do
      before do
        stub_request(:get, "http://localhost:3000/katello/authenticate?password=#{password}&username=#{username}").
            to_return(:status => 200, :body => "", :headers => {})
        post :login, :user => { :username => username, :password => password }
      end

      context "without return url" do
        it { response.must_be :redirect? }
        it { session[:username].must_equal(username) }
        it { cookies[:username].must_equal(username) }
      end

      context "with return url in session" do
        let(:url) { 'http://localhost:3001/test' }
        before do
          session[:return_url] = url
          post :login, :user => { :username => username, :password => password }
        end

        it { response.redirect_url.must_equal url }
      end
    end

    context "auth failed" do
      before do
        stub_request(:get, "http://localhost:3000/katello/authenticate?password=pass&username=#{username}").
            to_return(:status => 403, :body => "", :headers => {})
        post :login, :user => { :username => username, :password => 'pass' }
      end

      it { response.must_be :success? }
    end
  end

  describe "#provider" do
    let(:openid_params) { { 'openid.assoc_handle' => '{HMAC-SHA1}{51399cc7}{L/riIQ==}',
                            'openid.claimed_id'   => 'http://localhost:3002/user/admin',
                            'openid.identity'     => 'http://localhost:3002/user/admin',
                            'openid.mode'         => 'checkid_setup',
                            'openid.ns'           => 'http://specs.openid.net/auth/2.0',
                            'openid.ns.sreg'      => 'http://openid.net/extensions/sreg/1.1',
                            'openid.realm'        => 'http://localhost:3000',
                            'openid.return_to'    => 'http://localhost:3000/katello/' }
    }

    context "not logged user" do
      before do
        get :provider, openid_params
      end

      it "should redirect to login form" do
        response.must_be :redirect?
        response.redirect_url.must_include(root_path(:return_url => 'http://localhost:3000/katello/'))
      end
    end

    context "user is logged in alread" do
      before { session[:username] = username }

      context "user has no cookie" do
        before { get :provider, openid_params }

        it "should login user" do
          response.must_be :redirect?
          cookies[:username].must_equal username
          response.redirect_url.must_include('http://localhost:3000/katello/')
        end
      end

      context "user has cookie with same username as he is logged in" do
        before do
          cookies[:username] = username
          get :provider, openid_params
        end

        it "should login user" do
          response.must_be :redirect?
          cookies[:username].must_equal username
          response.redirect_url.must_include('http://localhost:3000/katello/')
          response.redirect_url.must_include('id_res') # success
        end
      end

      context "user has cookie with different username than he is logged in" do
        before do
          get :provider, openid_params.merge('openid.identity'   => 'http://localhost:3002/user/ares',
                                             'openid.calimed_id' => 'http://localhost:3002/user/ares')
        end

        it "fixes cookie and redirects back to relay party" do
          response.must_be :redirect?
          cookies[:username].must_equal username
          response.redirect_url.must_equal('http://localhost:3000/katello/')
          response.redirect_url.wont_include('id_res')
        end
      end

      context "Relay Party not authorized (whitelisted in configuration)" do
        before do
          get :provider, openid_params.merge('openid.realm'     => 'http://localhost:3005',
                                             'openid.return_to' => 'http://localhost:3005')
        end

        it "should redirect to root with error" do
          flash[:error].must_be :present?
          response.must_be :redirect?
        end
      end
    end
  end
end
