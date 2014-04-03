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
require 'component_helper'
require 'fileutils'
require 'java_buildpack/container/stack_tomcat'
require 'java_buildpack/repository/configured_item'
require 'java_buildpack/util/tokenized_version'

describe JavaBuildpack::Container::StackTomcat do
  include_context 'component_helper'

  let(:configuration) { { 'support' => support_configuration, "env" => env } }
  let(:env) { "cf" }
  let(:support_configuration) { {} }
  let(:support_uri) { 'test-support-uri' }
  let(:support_version) { '1.1.1' }

  before do
    allow(application_cache).to receive(:get).with(support_uri)
                                .and_yield(Pathname.new('spec/fixtures/stub-support.jar').open)
  end

  before do
    tokenized_version = JavaBuildpack::Util::TokenizedVersion.new(support_version)

    allow(JavaBuildpack::Repository::ConfiguredItem).to receive(:find_item).with(an_instance_of(String),
                                                                                 support_configuration) do |&block|
      block.call(tokenized_version) if block
    end.and_return([tokenized_version, support_uri])
  end

  it 'should detect Tomcat Deployable', app_fixture: 'container_stack_tomcat' do
    detected = component.detect

    expect(detected).to include("tomcat=#{version}")
    expect(detected).to include("tomcat-buildpack-support=#{support_version}")
  end

  it 'should not detect Tomcat Deployable', app_fixture: 'container_tomcat' do
    expect(component.detect).to be_nil
  end
  
  context do
    let(:version) { '7.0.47_10' }
  
    it 'should fail when a malformed version is detected',
       app_fixture: 'container_stack_tomcat' do
  
      expect { component.detect }.to raise_error /Malformed version/
    end
  end

  it 'should extract Tomcat from a GZipped TAR',
     app_fixture:   'container_stack_tomcat',
     cache_fixture: 'stub-tomcat.tar.gz' do

    component.compile

    expect(sandbox + 'bin/catalina.sh').to exist
    expect(sandbox + 'lib/tomcat_buildpack_support-1.1.1.jar').to exist
  end

  it 'should link the wars to the webapp directory',
     app_fixture:   'container_stack_tomcat',
     cache_fixture: 'stub-tomcat.tar.gz' do

    component.compile

    war = app_dir + '.java-buildpack/stack_tomcat/webapps/dude.war'

    expect(war).to exist
  end
  
  context do
    let(:env) { "root" }
    it 'should link the wars to the ROOT directory',
       app_fixture:   'container_stack_tomcat',
       cache_fixture: 'stub-tomcat.tar.gz' do
    
      component.compile
    
      war = app_dir + '.java-buildpack/stack_tomcat/webapps/ROOT.war'
    
      expect(war).to exist
    end
  end
  
  it 'should link the applib directory',
     app_fixture:   'container_stack_tomcat',
     cache_fixture: 'stub-tomcat.tar.gz' do
  
    component.compile
  
    jar = app_dir + '.java-buildpack/stack_tomcat/applib/some.jar'
  
    expect(jar).to exist
  end

  it 'should link the endorsed directory',
     app_fixture:   'container_stack_tomcat',
     cache_fixture: 'stub-tomcat.tar.gz' do
  
    component.compile
  
    jar = app_dir + '.java-buildpack/stack_tomcat/endorsed/endorsed.jar'
  
    expect(jar).to exist
  end
  
  it 'should link the conf directory entries',
     app_fixture:   'container_stack_tomcat',
     cache_fixture: 'stub-tomcat.tar.gz' do
  
    component.compile
  
    jar = app_dir + '.java-buildpack/stack_tomcat/conf/catalina.properties'
    expect(jar).to exist

    jar = app_dir + '.java-buildpack/stack_tomcat/conf/server.xml'
    expect(jar).to exist

  end
  
  context do
    let(:env) { "invalidarg" }
    it 'should fail because we have a jvm arg the supplies memory settings',
       app_fixture:   'container_stack_tomcat',
       cache_fixture: 'stub-tomcat.tar.gz' do
   
       expect{component.compile}.to raise_error(RuntimeError)
    end
  end

  it 'should return command',
     app_fixture: 'container_stack_tomcat',
     cache_fixture: 'stub-tomcat.tar.gz' do
       
    component.release

    expect(component.release).to eq("#{java_home.as_env_var} JAVA_OPTS=\"test-opt-2 test-opt-1 -Dsomevalue=10 -Dhttp.port=$PORT -Duser.timezone=America/Denver -Dsomevalue=10 -Dhttp.port=$PORT -Duser.timezone=America/Denver\" $PWD/.java-buildpack/stack_tomcat/bin/catalina.sh run")
                                        
    expect(java_opts).to include('-Duser.timezone=America/Denver')
  end

end
