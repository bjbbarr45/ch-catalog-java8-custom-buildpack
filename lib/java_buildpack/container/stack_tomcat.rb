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
require 'java_buildpack/container'
require 'java_buildpack/container/container_utils'
require 'java_buildpack/repository/configured_item'
require 'java_buildpack/util/application_cache'
require 'java_buildpack/util/format_duration'
require 'java_buildpack/container/tomcat'

module JavaBuildpack::Container

  # Encapsulates the detect, compile, and release functionality for Stack Tomcat applications.
  class StackTomcat < Tomcat

    # Creates an instance, passing in an arbitrary collection of options.
    #
    # @param [Hash] context the context that is provided to the instance
    # @option context [String] :app_dir the directory that the application exists in
    # @option context [String] :java_home the directory that acts as +JAVA_HOME+
    # @option context [Array<String>] :java_opts an array that Java options can be added to
    # @option context [String] :lib_directory the directory that additional libraries are placed in
    # @option context [Hash] :configuration the properties provided by the user
    def initialize(context)
      super(context)
      @tomcat_version, @tomcat_uri = StackTomcat.find_stack_tomcat(@app_dir, @configuration)
      @support_version, @support_uri = StackTomcat.find_stack_tomcat_support(@app_dir, @configuration)
    end

    # Detects whether this application is a Tomcat application.
    #
    # @return [String] returns +tomcat-<version>+ if and only if the application has a +WEB-INF+ directory, otherwise
    #                  returns +nil+
    def detect
      @tomcat_version ? ["Stack Tomcat", tomcat_id(@tomcat_version)] : nil
    end

    # Downloads and unpacks a Tomcat instance and support JAR
    #
    # @return [void]
    def compile
      env = @configuration[DEPLOYABLE_ENV]
      catalina = find_deployable_file("catalina.properties", env)
      download_tomcat
      remove_tomcat_files
      download_support
      catalina_props = properties(catalina)
      jvm_args = java_opts(env)
      jvm-args.each do |arg|
        ["-Xms", "-Xmx", "-XX:MaxMetaspaceSize", "-XX:MaxPermSize", "-Xss"].each do |param|
          raise "jvmargs.properties value '#{option}' uses the memory argument '#{param}'.  Memory customization should be done using the java-buildpack instead. (https://github.com/cloudfoundry/java-buildpack/blob/master/docs/jre-openjdk.md)" if arg.include? param
        end
      end
      @java_opts.concat java_opts(env)
      copy_wars_to_tomcat(catalina_props)
      copy_applib_dir
      copy_endorsed_dir
      copy_env_files_to_conf(env)
      link_stack_tomcat_libs
    end
    
    # Creates the command to run the Tomcat application.
    #
    # @return [String] the command to run the application.
    def release
      @java_opts << "-D#{KEY_HTTP_PORT}=$PORT"

      java_home_string = "JAVA_HOME=#{@java_home}"
      java_opts_string = ContainerUtils.space("JAVA_OPTS=\"#{ContainerUtils.to_java_opts_s(@java_opts)}\"")
      start_script_string = ContainerUtils.space(File.join(TOMCAT_HOME, 'bin', 'catalina.sh'))

      "#{java_home_string}#{java_opts_string}#{start_script_string} run"
    end

    privatel
    
      DEPLOYABLE_ENV = 'env'.freeze
      
      CONFIG_FILES = ["catalina.policy", "catalina.properties", "context.xml", "logging.properties", "server.xml", "web.xml"]
      
      def link_stack_tomcat_libs
        libs = ContainerUtils.libs(@app_dir, @lib_directory)

        if libs
          applib = File.join(tomcat_home, "lib")
          FileUtils.mkdir_p(applib) unless File.exists?(applib)
           
          libs.each { |lib|
            system "ln -sfn #{File.join '..', '..', lib} #{applib}"
          }
        end
      end
        
      def copy_env_files_to_conf(env)
        CONFIG_FILES.each do | file |
          deployable_file = find_deployable_file(file, env)
          unless deployable_file.nil? 
            puts "For #{file} using '#{File.basename(deployable_file)}' from deployable"
            system "ln -sfn #{File.join('..', '..', File.basename(deployable_file))} #{File.join(tomcat_home, 'conf', file)}"
          end
        end
      end
      
      def find_deployable_file(filename, env)
        raise "#{filename} is not an environment paramiterizable file." unless CONFIG_FILES.include?(filename)
        file_found = nil
        Dir.glob(File.join(@app_dir, "*#{filename}")) do |file|
          next unless File.file?(file)
          file_found = file if file_found.nil? && file == File.join(@app_dir, filename)   
          file_found = file if file == File.join(@app_dir, "#{env}.#{filename}")
        end
        file_found
      end
      
      def copy_applib_dir
        if File.exists?(File.join(@app_dir, "applib"))
          puts "Copying applib jars from deployable."
          FileUtils.mkdir_p(File.join(tomcat_home, "applib"))
          Dir.entries(File.join(@app_dir, "applib")).each do |file|
            next unless File.file?(File.join(@app_dir, "applib", file))
            system "ln -sfn #{File.join('..', '..', 'applib', file)} #{File.join(tomcat_home, 'applib', file)}"
          end
        end
      end
      
      def copy_endorsed_dir
        if File.exists?(File.join(@app_dir, "endorsed"))
          puts "Copying endorsed jars from deployable."
          FileUtils.mkdir_p(File.join(tomcat_home, "endorsed"))
          Dir.entries(File.join(@app_dir, "endorsed")).each do |file|
            next unless File.file?(File.join(@app_dir, "endorsed", file))
            system "ln -sfn #{File.join('..', '..', 'endorsed', file)} #{File.join(tomcat_home, 'endorsed', file)}"
          end
        end
      end

      
      def copy_wars_to_tomcat(catalina_props)
        Dir.glob(File.join(@app_dir, "*.war")) do |war_file|
          context_root = "ROOT"
          context_root = catalina_props["#{context_root}.contextRoot"] unless catalina_props["#{context_root}.contextRoot"].nil?
          context_root[0] = "" if context_root[0] == "/"
          context_root = "ROOT" if context_root.empty?
          context_root_war_name = "#{context_root.gsub(/\//, '#')}.war"
          FileUtils.mkdir_p(File.join(tomcat_home, "webapps"))
          puts "Deploying #{war_file} to webapps with context root #{context_root}"
          system "ln -sfn #{File.join('..', '..', File.basename(war_file))} #{File.join(tomcat_home, 'webapps', context_root_war_name)}"
        end
      end
      
      def remove_tomcat_files
        %w[NOTICE RELEASE-NOTES RUNNING.txt LICENSE temp/* webapps/* work/* logs bin/commons-daemon-native* bin/tomcat-native* lib/catalina-ha* lib/catalina-tribes* lib/tomcat-i18n-* lib/tomcat-dbcp*].each do |file|
          FileUtils.rm_rf(File.join(tomcat_home, file))
        end
      end

      def java_opts(env = "cf")
        props = {}
        props = properties(File.join(@app_dir, "jvmargs.properties")) if File.exists?(File.join(@app_dir, "jvmargs.properties"))
        args = {}
        props.map do |k,v|l
          next if k.rindex("jvmarg").nil?
          command_key = k[k.rindex("jvmarg")..-1]
          args[command_key] = v if k == command_key && !args.include?(command_key)
          args[command_key] = v if k == "#{env}.#{command_key}"
        end
        args.values
      end

      
      def properties(props_file)
        properties = {}
        IO.foreach(props_file) do |line|
          next if line.strip[0] == "#"
          if line =~ /([^=]*)=(.*)\/\/(.*)/ || line =~ /([^=]*)=(.*)/
            case $2
            when "true"
              properties[$1.strip] = true
            when "false"
              properties[$1.strip] = false
            else
              properties[$1.strip] = $2.nil? ? nil : $2.strip
            end
          end
        end
        properties
      end
      
      def self.find_stack_tomcat_support(app_dir, configuration)
        if deployable?(app_dir, configuration)
          version, uri = JavaBuildpack::Repository::ConfiguredItem.find_item(configuration[KEY_SUPPORT])
        else
          version = nil
          uri = nil
        end

        return version, uri # rubocop:disable RedundantReturn
      end


      def self.find_stack_tomcat(app_dir, configuration)
        if deployable?(app_dir, configuration)
          version, uri = JavaBuildpack::Repository::ConfiguredItem.find_item(configuration) do |candidate_version|
            fail "Malformed Tomcat version #{candidate_version}: too many version components" if candidate_version[3]
          end
        else
          version = nil
          uri = nil
        end

        return version, uri # rubocop:disable RedundantReturn
      rescue => e
        raise RuntimeError, "Tomcat container error: #{e.message}", e.backtrace
      end

      def self.deployable?(app_dir, configuration)
        env = configuration[DEPLOYABLE_ENV]
        war_exists = false
        catalina_properties_exists = false
        
        Dir.entries(app_dir).each do |file|
          next unless File.file?(File.join(app_dir, file))

          if file.end_with?(".war")
            war_exists = true
          end
          
          if file == "catalina.properties" || file == "#{env}.catalina.properties"
              catalina_properties_exists = true
          end
        end
        war_exists && catalina_properties_exists
      end
    end
end
