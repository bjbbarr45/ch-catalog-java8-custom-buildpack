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

module JavaBuildpack
  module Container
    # Encapsulates the detect, compile, and release functionality for Tomcat applications.
    class StackTomcat < JavaBuildpack::Component::BaseComponent

      def initialize(context)
        super(context)

        if supports?
          @tomcat_version, @tomcat_uri = JavaBuildpack::Repository::ConfiguredItem
                                         .find_item(@component_name, @configuration) do |candidate_version|
                                           candidate_version.check_size(3)
                                         end
        else
          @tomcat_version = nil
          @tomcat_uri = nil
        end
      end

      # (see JavaBuildpack::Component::BaseComponent#detect)
      def detect
        @tomcat_version ? [tomcat_id(@tomcat_version), 'StackTomcat=3.2+'] : nil
      end

# rubocop:disable all
      # (see JavaBuildpack::Component::BaseComponent#compile)
      def compile
        env = @configuration[DEPLOYABLE_ENV]
        catalina = find_deployable_file('catalina.properties', env)
        download_tomcat
        catalina_props = properties(catalina)
        unless catalina_props.key?('org.apache.tomcat.util.digester.PROPERTY_SOURCE')
          puts "Warning: #{catalina.basename} doesn't appear to specify a 'org.apache.tomcat.util.digester.PROPERTY_SOURCE'.  Resolving environment variables may not work."
        end
        jvm_args = java_opts(env)
        jvm_args.each do |arg|
          ['-Xms', '-Xmx', '-XX:PermSize', '-XX:MaxMetaspaceSize', '-XX:MetaspaceSize', '-XX:MaxPermSize', '-Xss', '-XX:-UseConcMarkSweepGC', '-XX:-UseParallelGC', '-XX:-UseParallelOldGC', '-XX:-UseSerialGC', '-XX:+UseG1GC'].each do |param|
            fail "jvmargs.properties value '#{arg}' uses the argument '#{param}'.  Memory and GC customization should be done using the java-buildpack instead. (https://github.com/cloudfoundry/java-buildpack/blob/master/docs/jre-openjdk.md)" if arg.include? param
          end
        end
        puts "Adding these jvmargs: #{jvm_args}"
        copy_wars_to_tomcat(catalina_props)
        copy_applib_dir
        copy_endorsed_dir
        copy_env_files_to_conf(env)
        @droplet.additional_libraries.link_to app_lib
      end

      # (see JavaBuildpack::Component::BaseComponent#release)
      def release
        @droplet.java_opts.concat parsed_java_opts(java_opts(@configuration[DEPLOYABLE_ENV]).join(' '))
        @droplet.java_opts.add_system_property 'http.port', '$PORT'
        @droplet.java_opts.add_system_property 'user.timezone', 'America/Denver'

        [
          @droplet.java_home.as_env_var,
          @droplet.java_opts.as_env_var,
          "$PWD/#{(@droplet.sandbox + 'bin/catalina.sh').relative_path_from(@droplet.root)}",
          'run'
        ].compact.join(' ')
      end

      private

      def tomcat_id(version)
        "#{Tomcat.to_s.dash_case}=#{version}"
      end

      def supports?
        deployable?
      end

      DEPLOYABLE_ENV = 'env'.freeze

      CONFIG_FILES = ['catalina.policy', 'catalina.properties', 'context.xml',
                        'logging.properties', 'server.xml', 'web.xml']

      def download_tomcat
        download(@tomcat_version, @tomcat_uri) { |file| expand file }
      end

      def parsed_java_opts(java_opts)
        java_opts.shellsplit.map do |java_opt|
          java_opt.gsub(/([\s])/, '\\\\\1')
        end
      end

      def expand(file)
        with_timing "Expanding Tomcat to #{@droplet.sandbox.relative_path_from(@droplet.root)}" do
          FileUtils.mkdir_p @droplet.sandbox
          shell "tar xzf #{file.path} -C #{@droplet.sandbox} --strip 1 --exclude webapps 2>&1"
        end
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
        CONFIG_FILES.each do |file|
          puts "Finding environment for #{file} and #{env}"
          deployable_file = find_deployable_file(file, env)
          next if deployable_file.nil?
          puts "Found file #{deployable_file}"
          puts "For #{file} using '#{deployable_file.basename}' from deployable"
          FileUtils.ln_sf(deployable_file.relative_path_from(tomcat_conf),  tomcat_conf + file)
        end
      end

      def copy_endorsed_dir
        endorsed = @application.root.join('endorsed')
        return unless endorsed.exist?
        puts 'Copying endorsed jars from deployable.'
        FileUtils.mkdir_p(tomcat_endorsed)
        endorsed.each_child do |file|
          next unless file.file?
          next unless file.basename.to_s.end_with?('.jar')
          FileUtils.ln_sf(file.relative_path_from(tomcat_endorsed),  tomcat_endorsed + file.basename)
        end
      end

      def copy_applib_dir
        applib = @application.root.join('applib')
        return unless applib.exist? && applib.directory?
        puts 'Copying applib jars from deployable.'
        applib.each_child do |file|
          next unless file.file?
          next unless file.basename.to_s.end_with?('.jar')
          @droplet.additional_libraries << file
        end
      end

      def copy_wars_to_tomcat(catalina_props)
        FileUtils.rm_rf webapps
        FileUtils.mkdir_p webapps
        war_found = false
        @application.root.each_child do |war_file|
          next unless war_file.file?
          next unless war_file.basename.to_s.end_with?('.war')
          war_found = true
          context_root = 'ROOT'
          war_file_name = war_file.basename.to_s.gsub(/.war/, '')
          context_root = catalina_props["#{war_file_name}.contextRoot"] unless catalina_props["#{war_file_name}.contextRoot"].nil?
          context_root[0] = '' if context_root[0] == '/'
          context_root = 'ROOT' if context_root.empty?
          unzip_dir_name = context_root.gsub(/\//, '#')
          unzip_dir = webapps+unzip_dir_name
          FileUtils.mkdir_p(unzip_dir)
          with_timing "Unzipping '#{war_file}' to into '#{unzip_dir}'" do
            shell "unzip -o #{war_file} -d #{unzip_dir}"
            FileUtils.rm_rf war_file
          end
        end
        STDERR.puts "Warning no .war files found in deployable." unless war_found
      end

      def find_deployable_file(filename, env)
        fail "#{filename} is not an environment paramiterizable file." unless CONFIG_FILES.include?(filename)
        file_found = nil
        @application.root.children.each do |file|
          next unless file.file?
          file_found = file if file_found.nil? && file.basename.to_s == filename
          file_found = file if file.basename.to_s == "#{env}.#{filename}"
        end
        file_found
      end
# rubocop:enable all

# rubocop:disable all
      def properties(props_file)
        properties = {}
        IO.foreach(props_file.to_path) do |line|
          next if line.strip[0] == '#'
          if line =~ /([^=]*)=(.*)\/\/(.*)/ || line =~ /([^=]*)=(.*)/
            case $2
            when 'true'
              properties[$1.strip] = true
            when 'false'
              properties[$1.strip] = false
            else
              properties[$1.strip] = $2.nil? ? nil : $2.strip
            end
          end
        end
        properties
      end

      def java_opts(env = 'cf')
        props = {}
        if @application.root.join('jvmargs.properties').exist?
          props = properties(@application.root.join('jvmargs.properties'))
        end
        args = {}
        props.map do |k, v|
          next if k.rindex('jvmarg').nil?
          command_key = k[k.rindex('jvmarg')..-1]
          args[command_key] = v if k == command_key && !args.include?(command_key)
          args[command_key] = v if k == "#{env}.#{command_key}"
        end
        args.values
      end

      def deployable?
        env = @configuration[DEPLOYABLE_ENV]
        catalina_properties_exists = false

        @application.root.each_child do |file|
          next unless file.file?

          next unless file.basename.to_s == 'catalina.properties' || file.basename.to_s == "#{env}.catalina.properties"
          catalina_properties_exists = true
        end
        catalina_properties_exists
      end

    end
  end

end
