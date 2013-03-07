class Configuration
  attr_accessor :config

  def initialize
    loader = Katello::Configuration::Loader.new(
        :config_file_paths        => %W(#{Rails.root}/config/sso.yml /etc/katello-sso/sso.yml),
        :validation               => lambda {|_| },
        :default_config_file_path => "#{Rails.root}/config/sso_defaults.yml"
    )
    @config = loader.config
  end

  def self.config
    @instance ||= new.config
  end
end