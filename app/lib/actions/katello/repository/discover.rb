module Actions
  module Katello
    module Repository
      class Discover < Actions::Base
        include Dynflow::Action::Cancellable

        input_format do
          param :url, String
          param :content_type, String
          param :upstream_username, String
          param :upstream_password, String
          param :search, String
        end

        output_format do
          param :repo_urls, array_of(String)
        end

        def plan(url, content_type, upstream_username, upstream_password, search)
          plan_self(url: url, content_type: content_type, upstream_username: upstream_username, upstream_password: upstream_password, search: search)
        end

        def run(event = nil)
          output[:repo_urls] = output[:repo_urls] || []
          output[:crawled] = output[:crawled] || []
          output[:to_follow] = output[:to_follow] || [input[:url]]

          repo_discovery = ::Katello::RepoDiscovery.new(input[:url], input[:content_type],
                                                        input[:upstream_username], input[:upstream_password],
                                                        input[:search], proxy,
                                                        output[:crawled], output[:repo_urls], output[:to_follow])

          match(event,
            (on nil do
              unless output[:to_follow].empty?
                repo_discovery.run(output[:to_follow].shift)
                suspend { |suspended_action| world.clock.ping suspended_action, 0.001 }
              end
            end),
            (on Dynflow::Action::Cancellable::Cancel do
              output[:repo_urls] = []
            end))
        end

        # @return <String> urls found by the action
        def task_input
          input[:url]
        end

        # @return [Array<String>] urls found by the action
        def task_output
          output[:repo_urls] || []
        end

        def proxy
          proxy_details = {}
          if (proxy = ::HttpProxy.default_global_content_proxy)
            uri = URI(proxy.url)
            proxy_details[:proxy_host] = "#{uri.host}#{uri.path}"
            proxy_details[:proxy_port] = uri.port
            proxy_details[:proxy_user] = proxy.username
            proxy_details[:proxy_password] = proxy.password
          end

          proxy_details
        end
      end
    end
  end
end
