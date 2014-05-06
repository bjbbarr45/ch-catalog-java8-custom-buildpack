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

require 'fileutils'
require 'java_buildpack/component/versioned_dependency_component'
require 'java_buildpack/framework'

module JavaBuildpack
  module Framework

    # Encapsulates the functionality for enabling zero-touch AppDynamics support.
    class AppDynamicsAgent < JavaBuildpack::Component::BaseComponent
      
      def initialize(context, &version_validator)
        super(context)
  
        if supports?
          @version, @uri = JavaBuildpack::Repository::ConfiguredItem
            .find_item(@component_name, @configuration)
          @pre_version, @pre_uri   = JavaBuildpack::Repository::ConfiguredItem
            .find_item(@component_name, @configuration['pre_agent'])
          @post_version, @post_uri = JavaBuildpack::Repository::ConfiguredItem
            .find_item(@component_name, @configuration['post_agent'])
        else
          @version = nil
          @uri     = nil
          @pre_version, @pre_uri = nil
          @post_version, @post_uri = nil
        end
      end
      
      def detect
        @version ? "#{AppDynamicsAgent.to_s.dash_case}=#{@version}" : nil
      end
  
      # @macro base_component_compile
      def compile
        download_zip(@version, @uri, false)
        download_jar(@pre_version, @pre_uri, "app-dynamics-hack-pre.jar", @droplet.sandbox,
                           'App Dynamics Pre Hack')
        download_jar(@post_version, @post_uri, "app-dynamics-hack-post.jar", @droplet.sandbox,
                           'App Dynamics Post Hack')
        @droplet.copy_resources
      end
  
      # @macro base_component_release
      def release
        credentials = @application.services.find_service(FILTER)['credentials']
        sm_credentials = @application.services.find_service(SM_FILTER)['credentials']
        java_opts   = @droplet.java_opts
  
        java_opts
        .add_javaagent(@droplet.sandbox + 'app-dynamics-hack-pre.jar')
        .add_javaagent(@droplet.sandbox + 'javaagent.jar')
        .add_javaagent(@droplet.sandbox + 'app-dynamics-hack-post.jar')
        .add_system_property('appdynamics.agent.applicationName', "'#{sm_credentials['smData']['PortfolioName']}'")
        .add_system_property('appdynamics.agent.tierName', "'#{sm_credentials['smData']['CIName']}'")
        .add_system_property('appdynamics.agent.nodeName',
                             "$(expr \"$VCAP_APPLICATION\" : '.*instance_id[\": ]*\"\\([a-z0-9]\\+\\)\".*')")
#        .add_system_property('appdynamics.agent.nodeName',
#                             "'#{@application.details['application_name']}[$(expr \"$VCAP_APPLICATION\" : '.*\"instance_index[\": ]*\\([0-9]\\+\\).*')]-[#{credentials['node-name-prefix']}]'")
        
        account_access_key(java_opts, credentials)
        account_name(java_opts, credentials)
        host_name(java_opts, credentials)
        port(java_opts, credentials)
        ssl_enabled(java_opts, credentials)
      end
  
      protected
  
      # @macro versioned_dependency_component_supports
      def supports?
        @application.services.one_service?(FILTER) &&
          @application.services.one_service?(SM_FILTER)
      end
  
      private
  
      FILTER = /app-dynamics/.freeze
      
      SM_FILTER = /servicemanager-service/.freeze
  
      def application_name
        @application.details['application_name']
      end
  
      def account_access_key(java_opts, credentials)
        account_access_key = credentials['account-access-key']
        java_opts.add_system_property 'appdynamics.agent.accountAccessKey', account_access_key if account_access_key
      end
  
      def account_name(java_opts, credentials)
        account_name = credentials['account-name']
        java_opts.add_system_property 'appdynamics.agent.accountName', account_name if account_name
      end
  
      def host_name(java_opts, credentials)
        host_name = credentials['host-name']
        fail "'host-name' credential must be set" unless host_name
        java_opts.add_system_property 'appdynamics.controller.hostName', host_name
      end
  
      def port(java_opts, credentials)
        port = credentials['port']
        java_opts.add_system_property 'appdynamics.controller.port', port if port
      end
  
      def ssl_enabled(java_opts, credentials)
        ssl_enabled = credentials['ssl-enabled']
        java_opts.add_system_property 'appdynamics.controller.ssl.enabled', ssl_enabled if ssl_enabled
      end
    end
  end
end