#!/usr/bin/ruby
#
# Use hprcu XML output to generate hprcu type
#
# Implementation plan:
# 1. Scan XML, extract names of options, convert into Puppet-friendly form (i.e. valid property names as per the Puppet grammar, defined in the Puppet code in grammar.ra)
# 2. (Optional) Invoke newproperty with each property name and check return code to confirm that the name is valid - emit helpful message if an invalid name has been generated or if there is a name clash
# 3. For each property, write to a new file the newproperty definition with appropriate name, valid and default values for the property

require 'puppet'
require 'rexml/document'
require 'erb'

puts <<EOT
# hprcu type

Puppet::Type.newtype(:hprcu) do
	@doc = "" # TODO

  # Type must be ensurable as we must use exists?, because as per p. 46 of
Puppet Types
  # and Providers: properties other than ensure are only *individually*
  # managed when ensure is set to present and the resource already
  # exists. When a resource state is absent, Puppet ignores any specified
  # resource property.
  ensurable

	newparam(:name, :namevar => true) do
	end

EOT

# Make (and remember) a Puppet-friendly property name, or if one already exists just 
# return it
$puppetFriendlyLookup = {}
def puppetFriendly(unfriendly)
	if ! $puppetFriendlyLookup.has_key?(unfriendly)
		friendly = unfriendly.downcase.gsub(/[- ()_\/:;]/,'')
		$puppetFriendlyLookup[unfriendly] = friendly
	end
	$puppetFriendlyLookup[unfriendly]
end

$newpropertyTemplate = <<EOT
	newproperty(<%= propertyName %>) do
		newvalues(<%= validValues.join(', ') %>)
	end

EOT

hprcuFilename = 'hprcu_sample.xml'
hprcuFileHandle = File.open('hprcu_sample.xml', 'r');
hprcuXml = REXML::Document.new hprcuFileHandle.read()

hprcuXml.root.elements.each('/hprcu/feature') { |feature| 
	propertyName = ''
	validValues = []
	propertyHash = {}

	feature.elements.each('feature_name') { |feature_name| 
		propertyName = ':' + puppetFriendly(feature_name.text)
	}

	feature.elements.each('option') { |option| 
		option.elements.each('option_name') { |on| 
			validValues.push(':' + puppetFriendly(on.text))
			propertyHash[option.attributes['option_id']] = ':' + puppetFriendly(on.text)
		}
	}

	puts ERB.new($newpropertyTemplate).result(binding)
}

puts <<EOT
end
EOT

# vim:sw=2:ts=2:et:
