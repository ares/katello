require 'test_helper'

describe User do
  before do
    @username = @password = 'admin'
    @user     = User.new(@username, @password)
    @url      = "http://locahost:3000/katello"
  end

  describe "#authenticate" do
    describe "successful response" do
      before do
        stub_request(:get, "#{@url}?password=#{@password}&username=#{@username}").
            to_return(:status => 200, :body => "", :headers => {})
      end
      it "returns true" do
        Configuration.config.backends.katello.stub :url, @url do
          @user.authenticate.must_equal true
        end
      end
    end

    describe "negative response" do
      before do
        stub_request(:get, "#{@url}?password=#{@password}&username=#{@username}").
            to_return(:status => 403, :body => "", :headers => {})
      end
      it "returns false" do
        Configuration.config.backends.katello.stub :url, @url do
          @user.authenticate.must_equal false
        end
      end
    end
  end

end