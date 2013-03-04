# A user that can authenticate against Katello system
class User
  attr_accessor :username, :password

  def initialize(username, password)
    self.username = username
    self.password = password
  end

  def authenticate
    true
  end
end