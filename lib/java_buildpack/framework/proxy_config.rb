# Encoding: utf-8
# Cloud Foundry Java Buildpack
# Copyright 2013 the original author or authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'java_buildpack/framework'
require 'shellwords'

module JavaBuildpack::Framework

  # Encapsulates the detect, compile, and release functionality for contributing custom Java options to an application
  # at runtime.
  class ProxyConfig < JavaBuildpack::BaseComponent

    # Creates an instance, passing in an arbitrary collection of options.
    #
    # @param [Hash] context the context that is provided to the instance
    # @option context [Array<String>] :java_opts an array that Java options can be added to
    # @option context [Hash] :configuration the properties provided by the user
    def initialize(context = {})
      super('ProxyConfig', context)
    end

    # Always add http proxy auto configuration
    #
    # @return [String]
    def detect
      CONTAINER_NAME
    end

    # Copy the http proxy agent jar and create the option script
    #
    # @return [void]
    def compile
      install_httpproxy_agent
      add_httpproxy_script
    end

    # Add $HTTPPROXY_OPTS to the start command if it gets set
    #
    # @return [void]
    def release
      @java_opts.concat ["$HTTPPROXY_OPTS"]
    end

    private

      CONTAINER_NAME = 'proxy_config'.freeze
      
      HTTPPROXY_PACKAGE =  "httpproxy-agent-1.1.jar".freeze

      #TODO add support for proper remote download
      def buildpack_cache_dir
        "/var/vcap/packages/buildpack_cache"
      end
      
      def agent_dir
        @application.component_directory 'agent'        
      end
      
      def install_httpproxy_agent
        FileUtils.mkdir_p(agent_dir)
        file_path = File.join(buildpack_cache_dir, HTTPPROXY_PACKAGE)
        FileUtils.cp(file_path, File.join(agent_dir, HTTPPROXY_PACKAGE))
      end
      
      def add_httpproxy_script
        FileUtils.mkdir_p(File.join(@app_dir, ".profile.d"))
        File.open(File.join(@app_dir, ".profile.d", "httpproxy_opts.sh"), "a") do |file|
          file.puts(
            <<-HTTPPROXY_BASH
if [ -n "$http_proxy" ] || [ -n "$https_proxy" ] ; then
  export HTTPPROXY_OPTS="#{httpproxy_opts}"
fi
               HTTPPROXY_BASH
          )
        end
      end
      
      def httpproxy_opts
        "-javaagent:#{agent_dir + HTTPPROXY_PACKAGE}"
      end
  end
end
