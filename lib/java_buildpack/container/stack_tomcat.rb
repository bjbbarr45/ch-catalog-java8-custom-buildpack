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
require 'java_buildpack/base_component'
require 'java_buildpack/container'
require 'java_buildpack/container/container_utils'
require 'java_buildpack/repository/configured_item'
require 'java_buildpack/util/application_cache'
require 'java_buildpack/util/format_duration'
require 'java_buildpack/util/java_main_utils'
require 'java_buildpack/util/resource_utils'

module JavaBuildpack::Container

  # Encapsulates the detect, compile, and release functionality for Tomcat applications.
  class StackTomcat < JavaBuildpack::BaseComponent

    def initialize(context)
      super('Stack Tomcat', context)
      puts "initialize Stack Tomcat"

      if supports?
        @tomcat_version, @tomcat_uri = JavaBuildpack::Repository::ConfiguredItem.find_item(@component_name, @configuration) { |candidate_version| candidate_version.check_size(3) }
        @support_version, @support_uri = JavaBuildpack::Repository::ConfiguredItem.find_item(@component_name, @configuration[KEY_SUPPORT])
      else
        @tomcat_version, @tomcat_uri = nil, nil
        @support_version, @support_uri = nil, nil
      end
    end

    def detect
      puts "detect Stack Tomcat"
      @tomcat_version && @support_version ? [tomcat_id(@tomcat_version), support_id(@support_version)] : nil
    end

    def compile
      puts "compile Stack Tomcat"
      env = @configuration[DEPLOYABLE_ENV]
      catalina = find_deployable_file("catalina.properties", env)
      download_tomcat
      download_support
      catalina_props = properties(catalina)
      if(!catalina_props.has_key?("org.apache.tomcat.util.digester.PROPERTY_SOURCE"))
        puts "Warning: #{catalina.basename.to_s} doesn't appear to specify a 'org.apache.tomcat.util.digester.PROPERTY_SOURCE'.  Resolving environment variables may not work."
      end
      jvm_args = java_opts(env)
      jvm_args.each do |arg|
        ["-Xms", "-Xmx", "-XX:MaxMetaspaceSize", "-XX:MaxPermSize", "-Xss"].each do |param|
          raise "jvmargs.properties value '#{arg}' uses the memory argument '#{param}'.  Memory customization should be done using the java-buildpack instead. (https://github.com/cloudfoundry/java-buildpack/blob/master/docs/jre-openjdk.md)" if arg.include? param
        end
      end
      @java_opts ||= []
      @java_opts.concat java_opts(env)
      copy_wars_to_tomcat(catalina_props)
      copy_applib_dir
      copy_endorsed_dir
      copy_env_files_to_conf(env)
      link_stack_tomcat_libs
    end

    def release
      puts "release Stack Tomcat"
      @java_opts << "-D#{KEY_HTTP_PORT}=$PORT"

      java_home_string = "JAVA_HOME=#{@java_home}"
      java_opts_string = ContainerUtils.space("JAVA_OPTS=\"#{ContainerUtils.to_java_opts_s(@java_opts)}\"")
      start_script_string = ContainerUtils.space(@application.relative_path_to(tomcat_home + 'bin' + 'catalina.sh'))

      "#{java_home_string}#{java_opts_string}#{start_script_string} run"
    end

    protected

    # The unique indentifier of the component, incorporating the version of the dependency (e.g. +tomcat-7.0.42+)
    #
    # @param [String] version the version of the dependency
    # @return [String] the unique identifier of the component
    def tomcat_id(version)
      "tomcat-#{version}"
    end

    # The unique indentifier of the component, incorporating the version of the dependency (e.g. +tomcat-buildpack-support-1.1.0+)
    #
    # @param [String] version the version of the dependency
    # @return [String] the unique identifier of the component
    def support_id(version)
      "tomcat-buildpack-support-#{version}"
    end

    # Whether or not this component supports this application
    #
    # @return [Boolean] whether or not this component supports this application
    def supports?
      deployable?
    end

    private

    KEY_HTTP_PORT = 'http.port'.freeze

    KEY_SUPPORT = 'support'.freeze

    WEB_INF_DIRECTORY = 'WEB-INF'.freeze

    DEPLOYABLE_ENV = 'env'.freeze
    
    CONFIG_FILES = ["catalina.policy", "catalina.properties", "context.xml", "logging.properties", "server.xml", "web.xml"]
    
    def download_tomcat
      download(@tomcat_version, @tomcat_uri) { |file| expand file }
    end

    def download_support
      download_jar(@support_version, @support_uri, support_jar_name, File.join(tomcat_home, 'lib'), 'Buildpack Tomcat Support')
    end

    def expand(file)
      expand_start_time = Time.now
      print "       Expanding Tomcat to #{@application.relative_path_to(tomcat_home)} "

      shell "rm -rf #{tomcat_home}"
      shell "mkdir -p #{tomcat_home}"
      
      excludes = ""

      ["NOTICE", "RELEASE-NOTES", "RUNNING.txt", "LICENSE", File.join("temp","*"), "webapps", File.join("work", "*"), "logs", File.join("bin", "commons-daemon-native*"), File.join("bin", "tomcat-native*"), File.join("lib", "catalina-ha*"), File.join("lib", "catalina-tribes*"), File.join("lib", "tomcat-i18n-*"), File.join("lib", "tomcat-dbcp*"), File.join('conf', 'server.xml'), File.join('conf', 'context.xml')].each do |file|
        excludes << " --exclude='#{file}'"
      end
      
      shell "tar xzf #{file.path} -C #{tomcat_home} --strip 1 #{excludes} 2>&1"
      

      JavaBuildpack::Util::ResourceUtils.copy_resources('tomcat', tomcat_home)
      puts "(#{(Time.now - expand_start_time).duration})"
    end

    def link_stack_tomcat_libs
      libs = ContainerUtils.libs(@app_dir, @lib_directory)
    
      if libs
        applib = File.join(tomcat_home, "lib")
        FileUtils.mkdir_p(applib) unless File.exist?(applib)
         
        libs.each { |lib|
          system "ln -sfn #{File.join '..', '..', lib} #{applib}"
        }
      end
    end


    def support_jar_name
      "#{support_id @support_version}.jar"
    end

    def tomcat_home
      @application.component_directory 'tomcat'
    end

    def webapps
      tomcat_home + 'webapps'
    end

    def deployable?
      env = @configuration[DEPLOYABLE_ENV]
      war_exists = false
      catalina_properties_exists = false
      
      puts "Application: #{@application.class}"
      
      @application.children.each do |file|
        next unless file.file?
    
        if file.basename.to_s.end_with?(".war")
          war_exists = true
        end
        
        if file.basename.to_s == "catalina.properties" || file.basename.to_s == "#{env}.catalina.properties"
            catalina_properties_exists = true
        end
      end
      war_exists && catalina_properties_exists
    end
    
    def find_deployable_file(filename, env)
      raise "#{filename} is not an environment paramiterizable file." unless CONFIG_FILES.include?(filename)
      file_found = nil
      @application.children.each do |file|
        next unless file.file?
        file_found = file if file_found.nil? && file.basename.to_s == filename   
        file_found = file if file.basename.to_s == "#{env}.#{filename}"
      end
      file_found
    end
    
    def properties(props_file)
      properties = {}
      IO.foreach(props_file.to_path) do |line|
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

    def java_opts(env = "cf")
      props = {}
      props = properties(@application.child("jvmargs.properties")) if @application.child("jvmargs.properties").exist?
      args = {}
      props.map do |k,v|
        next if k.rindex("jvmarg").nil?
        command_key = k[k.rindex("jvmarg")..-1]
        args[command_key] = v if k == command_key && !args.include?(command_key)
        args[command_key] = v if k == "#{env}.#{command_key}"
      end
      args.values
    end

    def copy_wars_to_tomcat(catalina_props)
      @application.children.each do |war_file|
        next unless war_file.file?
        next unless war_file.basename.to_s.end_with?(".war")
        context_root = "ROOT"
        war_file_name = war_file.basename.to_s.gsub(/.war/, "")
        context_root = catalina_props["#{war_file_name}.contextRoot"] unless catalina_props["#{war_file_name}.contextRoot"].nil?
        context_root[0] = "" if context_root[0] == "/"
        context_root = "ROOT" if context_root.empty?
        context_root_war_name = "#{context_root.gsub(/\//, '#')}.war"
        FileUtils.mkdir_p(webapps)
        puts "Deploying #{war_file} to webapps with context root #{context_root}"

        FileUtils.rm_rf webapps
        FileUtils.mkdir_p webapps
        new_war = webapps + context_root_war_name
        FileUtils.ln_sf(war_file.relative_path_from(webapps),  new_war)
      end
    end

    def copy_applib_dir
      applib = @application.child("applib")
      if applib.exist? && applib.directory?
        puts "Copying applib jars from deployable."
        tomcat_applib = tomcat_home + "applib"
        FileUtils.mkdir_p(tomcat_applib)
        applib.each_entry do |file|
          next unless file.file?
          FileUtils.ln_sf(file.relative_path_from(tomcat_applib),  tomcat_applib+file.basename)
        end
      end
    end

    def copy_endorsed_dir
      endorsed = @application.child("endorsed")
      if endorsed.exist?
        puts "Copying endorsed jars from deployable."
        tomcat_endorsed = tomcat_home + "endorsed"
        FileUtils.mkdir_p()
        endorsed.each_entry do |file|
          next unless file.file?
          FileUtils.ln_sf(file.relative_path_from(tomcat_endorsed),  tomcat_endorsed+file.basename)
        end
      end
    end
    
    def copy_env_files_to_conf(env)
      tomcat_conf = tomcat_home+"conf"
      CONFIG_FILES.each do | file |
        deployable_file = find_deployable_file(file, env)
        unless deployable_file.nil? 
          puts "For #{file} using '#{deployable_file.basename.to_s}' from deployable"
          FileUtils.ln_sf(deployable_file.relative_path_from(tomcat_conf),  tomcat_conf+file)
        end
      end
    end
  end
end
