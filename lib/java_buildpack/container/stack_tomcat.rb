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
require 'java_buildpack/component/base_component'
require 'java_buildpack/container'
require 'java_buildpack/container/tomcat'
require 'java_buildpack/repository/configured_item'
require 'java_buildpack/util/dash_case'
require 'java_buildpack/util/java_main_utils'

module JavaBuildpack::Container

  # Encapsulates the detect, compile, and release functionality for Tomcat applications.
  class StackTomcat < JavaBuildpack::Component::BaseComponent

    def initialize(context)
      super(context)

      if supports?
        @tomcat_version, @tomcat_uri   = JavaBuildpack::Repository::ConfiguredItem
        .find_item(@component_name, @configuration) { |candidate_version| candidate_version.check_size(3) }
        @support_version, @support_uri = JavaBuildpack::Repository::ConfiguredItem
        .find_item(@component_name, @configuration['support'])
      else
        @tomcat_version, @tomcat_uri   = nil, nil
        @support_version, @support_uri = nil, nil
      end
    end

    def detect
      @tomcat_version && @support_version ? [tomcat_id(@tomcat_version), support_id(@support_version), "StackTomcat=3.2+"] : nil
    end
    
    def compile
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
      #@droplet.java_opts.concat parsed_java_opts(jvm_args.join(" "))
      puts "Droplet java_options now include: #{@droplet.java_opts}"
      copy_wars_to_tomcat(catalina_props)
      copy_applib_dir
      copy_endorsed_dir
      copy_env_files_to_conf(env)
      @droplet.additional_libraries.link_to app_lib
    end

    def release
      @droplet.java_opts.concat parsed_java_opts(java_opts(@configuration[DEPLOYABLE_ENV]).join(" "))
      @droplet.java_opts.add_system_property 'http.port', '$PORT'
      @droplet.java_opts.add_system_property 'user.timezone', 'America/Denver'

      [
          @droplet.java_home.as_env_var,
          @droplet.java_opts.as_env_var,
          "$PWD/#{(@droplet.sandbox + 'bin/catalina.sh').relative_path_from(@droplet.root)}",
          'run'
      ].compact.join(' ')
    end

    protected
    
    def tomcat_id(version)
      "#{Tomcat.to_s.dash_case}=#{version}"
    end
    
    def support_id(version)
      "tomcat-buildpack-support=#{version}"
    end
    
    def supports?
      deployable?
    end

    private
    
    DEPLOYABLE_ENV = 'env'.freeze
    
    CONFIG_FILES = ["catalina.policy", "catalina.properties", "context.xml", "logging.properties", "server.xml", "web.xml"]
    
    def download_tomcat
      download(@tomcat_version, @tomcat_uri) { |file| expand file }
    end

    def download_support
      download_jar(@support_version, @support_uri, support_jar_name, @droplet.sandbox + 'lib',
                   'Buildpack Stack Tomcat Support')
    end
    
    def parsed_java_opts(java_opt)
      java_opt.shellsplit.map do |java_opt|
        java_opt.gsub(/([\s])/, '\\\\\1')
      end
    end

    def expand(file)
      with_timing "Expanding Tomcat to #{@droplet.sandbox.relative_path_from(@droplet.root)}" do
        FileUtils.mkdir_p @droplet.sandbox
        shell "tar xzf #{file.path} -C #{@droplet.sandbox} --strip 1 --exclude webapps 2>&1"
      end
    end
    
    def root
      webapps + 'ROOT'
    end
  
    def support_jar_name
      "tomcat_buildpack_support-#{@support_version}.jar"
    end
  
    def tomcat_datasource_jar
      tomcat_lib + 'tomcat-jdbc.jar'
    end
  
    def tomcat_lib
      @droplet.sandbox + 'lib'
    end
  
    def webapps
      @droplet.sandbox + 'webapps'
    end
    
    def app_lib
      @droplet.sandbox + 'applib'
    end
    
    def tomcat_endorsed
      @droplet.sandbox + 'endorsed'
    end
    
    def tomcat_conf
      @droplet.sandbox + 'conf'
    end
    
    def copy_env_files_to_conf(env)
      FileUtils.mkdir_p(tomcat_conf)
      CONFIG_FILES.each do | file |
        puts "Finding environment for #{file} and #{env}"
        deployable_file = find_deployable_file(file, env)
        unless deployable_file.nil? 
          puts "Found file #{deployable_file}"
          puts "For #{file} using '#{deployable_file.basename.to_s}' from deployable"
          FileUtils.ln_sf(deployable_file.relative_path_from(tomcat_conf),  tomcat_conf+file)
        end
      end
    end

    def copy_endorsed_dir
      endorsed = @application.root.join("endorsed")
      if endorsed.exist?
        puts "Copying endorsed jars from deployable."
        FileUtils.mkdir_p(tomcat_endorsed)
        endorsed.each_child do |file|
          next unless file.file?
          next unless file.basename.to_s.end_with?(".jar")
          FileUtils.ln_sf(file.relative_path_from(tomcat_endorsed),  tomcat_endorsed+file.basename)
        end
      end
    end
    
    def copy_applib_dir
      applib = @application.root.join("applib")
      if applib.exist? && applib.directory?
        puts "Copying applib jars from deployable."
        applib.each_child do |file|
          next unless file.file?
          next unless file.basename.to_s.end_with?(".jar")
          @droplet.additional_libraries << file
        end
      end
    end
    
    def copy_wars_to_tomcat(catalina_props)
      @application.root.each_child do |war_file|
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
    
    def find_deployable_file(filename, env)
      raise "#{filename} is not an environment paramiterizable file." unless CONFIG_FILES.include?(filename)
      file_found = nil
      @application.root.children.each do |file|
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
      props = properties(@application.root.join("jvmargs.properties")) if @application.root.join("jvmargs.properties").exist?
      args = {}
      props.map do |k,v|
        next if k.rindex("jvmarg").nil?
        command_key = k[k.rindex("jvmarg")..-1]
        args[command_key] = v if k == command_key && !args.include?(command_key)
        args[command_key] = v if k == "#{env}.#{command_key}"
      end
      #puts "We found these args in the jvmargs.properties file: #{args}"
      args.values
    end
    
    def deployable?
      env = @configuration[DEPLOYABLE_ENV]
      war_exists = false
      catalina_properties_exists = false
    
      @application.root.each_child do |file|
        next unless file.file?
    
        if file.to_s.end_with?(".war")
          war_exists = true
        end
        
        if file.basename.to_s == "catalina.properties" || file.basename.to_s == "#{env}.catalina.properties"
            catalina_properties_exists = true
        end
      end
      war_exists && catalina_properties_exists
    end

  end

end
