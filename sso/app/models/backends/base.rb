class Backends::Base
  # runs authentication through all enabled backends
  def self.authenticate(opts)
    Configuration.config.backends.enabled.any? do |name|
      begin
        backend = "Backends::#{name.to_s.camelize}".constantize
      rescue NameError => e
        Rails.logger.error "Wrong backend name #{name}, check application configuration, ignoring..."
        Rails.logger.debug e.backtrace.join("\n")
        next(false)
      end

      backend.new.authenticate(opts)
    end
  end

  # should authenticate user and return true or false as a result
  # opts should contain all credentials needed for backend
  # real authentication backends should implement this method
  def authenticate(opts)
    raise NotImplementedError
  end
end