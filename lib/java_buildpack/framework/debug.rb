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

require 'java_buildpack/component/base_component'
require 'java_buildpack/framework'
require 'java_buildpack/util/dash_case'
require 'shellwords'

module JavaBuildpack::Framework

  # Encapsulates the functionality for contributing custom Java options to an application.
  class Debug < JavaBuildpack::Component::BaseComponent

    def detect
      Debug.to_s.dash_case
    end

    def compile
    end

    def release
      @droplet.java_opts.concat ["$(eval 'if [ -n \"$VCAP_DEBUG_MODE\" ]; then if [ \"$VCAP_DEBUG_MODE\" = \"run\" ]; then echo \"#{debug_run_opts}\"; elif [ \"$VCAP_DEBUG_MODE\" = \"suspend\" ]; then echo \"#{debug_suspend_opts}\"; fi fi')"]
    end
    
    private
  
    def debug_run_opts
      "-Xdebug -Xrunjdwp:transport=dt_socket,address=$VCAP_DEBUG_PORT,server=y,suspend=n"
    end
  
    def debug_suspend_opts
      "-Xdebug -Xrunjdwp:transport=dt_socket,address=$VCAP_DEBUG_PORT,server=y,suspend=y"
    end
  end
end
