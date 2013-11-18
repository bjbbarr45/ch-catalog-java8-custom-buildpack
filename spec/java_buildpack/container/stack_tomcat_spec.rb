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

require 'spec_helper'
require 'fileutils'
require 'java_buildpack/container/stack_tomcat'

module JavaBuildpack::Container

  describe StackTomcat do

    TOMCAT_VERSION = JavaBuildpack::Util::TokenizedVersion.new('7.0.40')

    TOMCAT_DETAILS = [TOMCAT_VERSION, 'test-tomcat-uri']

    SUPPORT_VERSION = JavaBuildpack::Util::TokenizedVersion.new('1.0.0')

    SUPPORT_DETAILS = [SUPPORT_VERSION, 'test-support-uri']

    let(:application_cache) { double('ApplicationCache') }

    before do
      $stdout = StringIO.new
      $stderr = StringIO.new
    end

    it 'should detect Tomcat Deployable' do
      JavaBuildpack::Repository::ConfiguredItem.stub(:find_item) { |&block| block.call(TOMCAT_VERSION) if block }
      .and_return(TOMCAT_DETAILS, SUPPORT_DETAILS)
      detected = StackTomcat.new(
        app_dir: 'spec/fixtures/container_stack_tomcat',
        application: JavaBuildpack::Application.new('spec/fixtures/container_stack_tomcat'),
        configuration: {"env" => "cf"}
      ).detect

      expect(detected).to include('tomcat-7.0.40')
    end

    it 'should not detect Tomcat Deployable' do
      detected = StackTomcat.new(
        app_dir: 'spec/fixtures/container_main',
        application: JavaBuildpack::Application.new('spec/fixtures/container_main'),
        configuration: {}
      ).detect

      expect(detected).to be_nil
    end

    
    it 'should extract Tomcat from a GZipped TAR' do
      Dir.mktmpdir do |root|
        FileUtils.touch(File.join(root, 'dude.war'))
        FileUtils.touch(File.join(root, 'catalina.properties'))

        JavaBuildpack::Repository::ConfiguredItem.stub(:find_item) { |&block| block.call(TOMCAT_VERSION) if block }
        .and_return(TOMCAT_DETAILS, SUPPORT_DETAILS)

        JavaBuildpack::Util::ApplicationCache.stub(:new).and_return(application_cache)
        application_cache.stub(:get).with('test-tomcat-uri').and_yield(File.open('spec/fixtures/stub-tomcat.tar.gz'))
        application_cache.stub(:get).with('test-support-uri').and_yield(File.open('spec/fixtures/stub-support.jar'))

        StackTomcat.new(
          app_dir: root,
          application: JavaBuildpack::Application.new(root),
          configuration: {}
        ).compile

        tomcat_dir = File.join root, '.tomcat'
        conf_dir = File.join tomcat_dir, 'conf'

        catalina = File.join tomcat_dir, 'bin', 'catalina.sh'
        expect(File.exists?(catalina)).to be_true

        context = File.join conf_dir, 'context.xml'
        expect(File.exists?(context)).to be_true

        server = File.join conf_dir, 'server.xml'
        expect(File.exists?(server)).to be_true

        support = File.join tomcat_dir, 'lib', 'tomcat-buildpack-support-1.0.0.jar'
        expect(File.exists?(support)).to be_true
      end
    end

    it 'should link the application directory to the ROOT webapp' do
      Dir.mktmpdir do |root|
        FileUtils.touch(File.join(root, 'dude.war'))
        FileUtils.touch(File.join(root, 'catalina.properties'))

        JavaBuildpack::Repository::ConfiguredItem.stub(:find_item) { |&block| block.call(TOMCAT_VERSION) if block }
        .and_return(TOMCAT_DETAILS, SUPPORT_DETAILS)

        JavaBuildpack::Util::ApplicationCache.stub(:new).and_return(application_cache)
        application_cache.stub(:get).with('test-tomcat-uri').and_yield(File.open('spec/fixtures/stub-tomcat.tar.gz'))
        application_cache.stub(:get).with('test-support-uri').and_yield(File.open('spec/fixtures/stub-support.jar'))

        StackTomcat.new(
          app_dir: root,
          application: JavaBuildpack::Application.new(root),
          configuration: {}
        ).compile

        root_webapp = File.join(root, '.tomcat', 'webapps', 'ROOT.war')
        expect(File.exists?(root_webapp)).to be_true
      end
    end

    it 'should link additional libraries to the ROOT webapp' do
      Dir.mktmpdir do |root|
        FileUtils.touch(File.join(root, 'dude.war'))
        FileUtils.touch(File.join(root, 'catalina.properties'))
        applib = File.join(root,".tomcat", "lib")
        FileUtils.mkdir_p applib
        lib_directory = File.join root, '.lib'
        Dir.mkdir lib_directory

        Dir['spec/fixtures/additional_libs/*'].each { |file| system "cp #{file} #{lib_directory}" }

        JavaBuildpack::Repository::ConfiguredItem.stub(:find_item) { |&block| block.call(TOMCAT_VERSION) if block }
        .and_return(TOMCAT_DETAILS, SUPPORT_DETAILS)

        JavaBuildpack::Util::ApplicationCache.stub(:new).and_return(application_cache)
        application_cache.stub(:get).with('test-tomcat-uri').and_yield(File.open('spec/fixtures/stub-tomcat.tar.gz'))
        application_cache.stub(:get).with('test-support-uri').and_yield(File.open('spec/fixtures/stub-support.jar'))

        StackTomcat.new(
          app_dir: root,
          application: JavaBuildpack::Application.new(root),
          lib_directory: lib_directory,
          configuration: {}
        ).compile

        lib = File.join root, '.tomcat', 'lib'
        test_jar_1 = File.join lib, 'test-jar-1.jar'
        test_jar_2 = File.join lib, 'test-jar-2.jar'
        test_text = File.join lib, 'test-text.txt'

        expect(File.exists?(test_jar_1)).to be_true
        expect(File.symlink?(test_jar_1)).to be_true
        expect(File.readlink(test_jar_1)).to eq('../../.lib/test-jar-1.jar')

        expect(File.exists?(test_jar_2)).to be_true
        expect(File.symlink?(test_jar_2)).to be_true
        expect(File.readlink(test_jar_2)).to eq('../../.lib/test-jar-2.jar')

        expect(File.exists?(test_text)).to be_false
      end
    end
    
    it 'should link applib and endorsed directories' do
      Dir.mktmpdir do |root|
        FileUtils.touch(File.join(root, 'dude.war'))
        FileUtils.touch(File.join(root, 'catalina.properties'))
        applib = File.join(root, 'applib')
        FileUtils.mkdir_p(applib)
        endorsed = File.join(root, 'endorsed')
        FileUtils.mkdir_p(endorsed)

        Dir['spec/fixtures/additional_libs/*'].each { |file| system "cp #{file} #{applib}" }
        Dir['spec/fixtures/additional_libs/*'].each { |file| system "cp #{file} #{endorsed}" }
    
        JavaBuildpack::Repository::ConfiguredItem.stub(:find_item) { |&block| block.call(TOMCAT_VERSION) if block }
        .and_return(TOMCAT_DETAILS, SUPPORT_DETAILS)
    
        JavaBuildpack::Util::ApplicationCache.stub(:new).and_return(application_cache)
        application_cache.stub(:get).with('test-tomcat-uri').and_yield(File.open('spec/fixtures/stub-tomcat.tar.gz'))
        application_cache.stub(:get).with('test-support-uri').and_yield(File.open('spec/fixtures/stub-support.jar'))
    
        StackTomcat.new(
          app_dir: root,
          application: JavaBuildpack::Application.new(root),
          configuration: {}
        ).compile
    
        applib = File.join root, '.tomcat', 'applib'
        applib_test_jar_1 = File.join applib, 'test-jar-1.jar'
        applib_test_jar_2 = File.join applib, 'test-jar-2.jar'
        applib_test_text = File.join applib, 'test-text.txt'
    
        expect(File.exists?(applib_test_jar_1)).to be_true
        expect(File.symlink?(applib_test_jar_1)).to be_true
        expect(File.readlink(applib_test_jar_1)).to eq('../../applib/test-jar-1.jar')
    
        expect(File.exists?(applib_test_jar_2)).to be_true
        expect(File.symlink?(applib_test_jar_2)).to be_true
        expect(File.readlink(applib_test_jar_2)).to eq('../../applib/test-jar-2.jar')
    
        expect(File.exists?(applib_test_text)).to be_false

        endorsed_lib = File.join root, '.tomcat', 'endorsed'
        endorsed_test_jar_1 = File.join endorsed_lib, 'test-jar-1.jar'
        endorsed_test_jar_2 = File.join endorsed_lib, 'test-jar-2.jar'
        endorsed_test_text = File.join endorsed_lib, 'test-text.txt'
    
        expect(File.exists?(endorsed_test_jar_1)).to be_true
        expect(File.symlink?(endorsed_test_jar_1)).to be_true
        expect(File.readlink(endorsed_test_jar_1)).to eq('../../endorsed/test-jar-1.jar')
    
        expect(File.exists?(endorsed_test_jar_2)).to be_true
        expect(File.symlink?(endorsed_test_jar_2)).to be_true
        expect(File.readlink(endorsed_test_jar_2)).to eq('../../endorsed/test-jar-2.jar')
    
        expect(File.exists?(endorsed_test_text)).to be_false

      end
    end
  end
end
