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
require 'java_buildpack/framework/debug'

module JavaBuildpack::Framework

  describe Debug do

    let(:java_opts) { [] }

    it 'should detect always detect' do
      detected = Debug.new(
          java_opts: java_opts,
          configuration: {}
      ).detect

      expect(detected).to eq('debug')
    end

    it 'should add split java_opts to context' do
      Debug.new(
          java_opts: java_opts,
          configuration: {}
      ).release

      expect(java_opts).to include('$DEBUG_OPTS')
    end
  end

end
