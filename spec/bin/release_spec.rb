# frozen_string_literal: true

# Cloud Foundry Java Buildpack
# Copyright 2013-2020 the original author or authors.
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
require 'integration_helper'

describe 'release script', :integration do # rubocop:disable RSpec/DescribeClass
  include_context 'with integration help'

  it 'returns zero if success',
     app_fixture: 'integration_valid' do

    run("bin/release #{app_dir}") { |status| expect(status).to be_success }
  end

  it 'fails to release when no containers detect' do
    run("bin/release #{app_dir}") do |status|
      expect(status).not_to be_success
      expect(stderr.string).to match(/No container can run this application/)
    end
  end

end
