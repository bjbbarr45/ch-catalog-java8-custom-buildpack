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
require 'java_buildpack/base_component'
require 'shellwords'

module JavaBuildpack::Framework

  # Encapsulates the detect, compile, and release functionality for contributing custom Java options to an application
  # at runtime.
  class JMX < JavaBuildpack::BaseComponent

    # Creates an instance, passing in an arbitrary collection of options.
    #
    # @param [Hash] context the context that is provided to the instance
    # @option context [Array<String>] :java_opts an array that Java options can be added to
    # @option context [Hash] :configuration the properties provided by the user
    def initialize(context = {})
      super('JMX', context)
    end

    # Always add JMX config if it is a java app
    #
    # @return [String] returns +java-opts+ if Java options have been set by the user
    def detect
      CONTAINER_NAME
    end

    # Ensures that none of the Java options specify memory configurations
    #
    # @return [void]
    def compile
      install_jmxmp_agent
      add_jmx_script
    end

    # Add $JMX_OPTS to the start command if it gets set
    #
    # @return [void]
    def release
      @java_opts.concat ["$JMX_OPTS"]
    end

    private

      CONTAINER_NAME = 'jmx'.freeze
      
      JMXMP_PACKAGE =  "jmxmp-agent-1.0.jar".freeze

      #TODO add support for proper remote download
      def buildpack_cache_dir
        "/var/vcap/packages/buildpack_cache"
      end
      
      def agent_dir
        @application.component_directory 'agent'        
      end
      
      def install_jmxmp_agent
        FileUtils.mkdir_p(agent_dir)
        file_path = File.join(buildpack_cache_dir, JMXMP_PACKAGE)
        FileUtils.cp(file_path, File.join(agent_dir, JMXMP_PACKAGE))
      end
      
      def add_jmx_script
        FileUtils.mkdir_p(File.join(@app_dir, ".profile.d"))
        File.open(File.join(@app_dir, ".profile.d", "jmx_opts.sh"), "a") do |file|
          file.puts(
            <<-JMX_BASH
if [ -n "$VCAP_CONSOLE_PORT" ]; then
  export JMX_OPTS="#{jmx_opts}"
fi
               JMX_BASH
          )
        end
      end
      
      def jmx_opts
        "-javaagent:#{(agent_dir + JMXMP_PACKAGE).relative_path_from(@app_dir)} -Dorg.lds.cloudfoundry.jmxmp.host=$VCAP_CONSOLE_IP -Dorg.lds.cloudfoundry.jmxmp.port=$VCAP_CONSOLE_PORT"
      end
  end
end
