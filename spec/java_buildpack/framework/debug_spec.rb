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
require 'java_buildpack/framework/debug'

describe JavaBuildpack::Framework::Debug do
  include_context 'component_helper'

  it 'detect always detect' do
    expect(component.detect).to eq('debug')
  end

  context do
    it 'add split java_opts to context' do
      component.release

      # We only want to check the opt that we add
      expect(java_opts.last).to include('$VCAP_DEBUG_PORT')
    end
  end
end
