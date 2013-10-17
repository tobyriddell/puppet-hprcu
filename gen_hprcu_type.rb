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

$puppetFriendlyLookup = {}

$newpropertyTemplate = <<EOT
	newproperty(<%= propertyName %>) do
		defaultto <%= defaultValue %>
		newvalues(<%= validValues.join(', ') %>)
	end

EOT

# Make (and remember) a Puppet-friendly property name, or if one already exists just 
# return it
def puppetFriendly(unfriendly)
	if ! $puppetFriendlyLookup.has_key?(unfriendly)
		friendly = unfriendly.downcase.gsub(/[- ()_\/:;]/,'')
		$puppetFriendlyLookup[unfriendly] = friendly
	end
	$puppetFriendlyLookup[unfriendly]
end

hprcuFilename = 'hprcu_sample.xml'
hprcuFileHandle = File.open('hprcu_sample.xml', 'r');
hprcuXml = REXML::Document.new hprcuFileHandle.read()

puts <<EOT
# hprcu type

Puppet::Type.newtype(:hprcu) do
	@doc = "" # TODO

	newparam(:name, :namevar => true) do
	end

EOT

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

	defaultValue = propertyHash[feature.attributes['sys_default_option_id']]

	puts ERB.new($newpropertyTemplate).result(binding)
}

puts <<EOT
end
EOT
