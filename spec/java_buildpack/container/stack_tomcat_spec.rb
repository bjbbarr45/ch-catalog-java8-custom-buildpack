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

  let(:configuration) { { 'env' => env } }
  let(:env) { 'cf' }

  it 'detect Tomcat Deployable', app_fixture: 'container_stack_tomcat' do
    detected = component.detect

    expect(detected).to include("tomcat=#{version}")
  end

  it 'not detect Tomcat Deployable', app_fixture: 'container_tomcat' do
    expect(component.detect).to be_nil
  end

  context do
    let(:version) { '7.0.47_10' }

    it 'fail when a malformed version is detected',
       app_fixture: 'container_stack_tomcat' do

      expect { component.detect }.to raise_error(/Malformed version/)
    end
  end

  it 'extract Tomcat from a GZipped TAR',
     app_fixture:   'container_stack_tomcat',
     cache_fixture: 'stub-tomcat.tar.gz' do

    component.compile

    expect(sandbox + 'bin/catalina.sh').to exist
  end

  it 'link the wars to the webapp directory',
     app_fixture:   'container_stack_tomcat',
     cache_fixture: 'stub-tomcat.tar.gz' do

    component.compile

    file_in_war = app_dir + '.java-buildpack/stack_tomcat/webapps/dude/file.txt'

    expect(file_in_war).to exist
  end

  context do
    let(:env) { 'root' }

    it 'link the wars to the ROOT directory',
       app_fixture:   'container_stack_tomcat',
       cache_fixture: 'stub-tomcat.tar.gz' do

      component.compile

      file_in_war = app_dir + '.java-buildpack/stack_tomcat/webapps/ROOT/file.txt'

      expect(file_in_war).to exist
    end
  end

  context do
    let(:env) { 'subdir' }

    it 'link the wars to the ROOT directory',
       app_fixture:   'container_stack_tomcat',
       cache_fixture: 'stub-tomcat.tar.gz' do

      component.compile

      file_in_war = app_dir + '.java-buildpack/stack_tomcat/webapps/sub#dir/file.txt'

      expect(file_in_war).to exist
    end
  end

  it 'link the applib directory',
     app_fixture:   'container_stack_tomcat',
     cache_fixture: 'stub-tomcat.tar.gz' do

    component.compile

    jar = app_dir + '.java-buildpack/stack_tomcat/applib/some.jar'

    expect(jar).to exist
  end

  it 'link the endorsed directory',
     app_fixture:   'container_stack_tomcat',
     cache_fixture: 'stub-tomcat.tar.gz' do

    component.compile

    jar = app_dir + '.java-buildpack/stack_tomcat/endorsed/endorsed.jar'

    expect(jar).to exist
  end

  it 'link the conf directory entries',
     app_fixture:   'container_stack_tomcat',
     cache_fixture: 'stub-tomcat.tar.gz' do

    component.compile

    jar = app_dir + '.java-buildpack/stack_tomcat/conf/catalina.properties'
    expect(jar).to exist

    jar = app_dir + '.java-buildpack/stack_tomcat/conf/server.xml'
    expect(jar).to exist

  end

  context do
    let(:env) { 'invalidarg' }

    it 'fail because we have a jvm arg the supplies memory settings',
       app_fixture:   'container_stack_tomcat',
       cache_fixture: 'stub-tomcat.tar.gz' do
      expect { component.compile }.to raise_error(RuntimeError)
    end
  end

  it 'return command',
     app_fixture: 'container_stack_tomcat',
     cache_fixture: 'stub-tomcat.tar.gz' do

    component.release

# rubocop:disable all
    expect(component.release).to eq("#{java_home.as_env_var} JAVA_OPTS=\"test-opt-2 test-opt-1 -Dsomevalue=10 -Dhttp.port=$PORT -Duser.timezone=America/Denver -Dsomevalue=10 -Dhttp.port=$PORT -Duser.timezone=America/Denver\" $PWD/.java-buildpack/stack_tomcat/bin/catalina.sh run")
# rubocop:enable all
    expect(java_opts).to include('-Duser.timezone=America/Denver')
  end

end
