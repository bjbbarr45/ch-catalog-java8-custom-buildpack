# Cloud Foundry Java Buildpack
This is the LDS fork of the cloud foundry Java Buildpack https://github.com/cloudfoundry/java-buildpack

The main changes in the LDS Fork of the build pack are:
* Support for [Stack 3.x Tomcat Deployable](https://code.lds.org/nexus/content/sites/maven-sites/stack/modules/tomcat-maven-plugin/3.4.1/tomcat-deployable.html)
* Support for Debug and JMX Console listening
* Support for App Dynamics ICS standard application and tier name
* Use G1 garbage collector by default
* Point to our internal [buildpack artifact cache](http://cfdownloads.ldschurch.org/java-buildpack/)