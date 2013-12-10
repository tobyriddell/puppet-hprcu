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

# Parse command line
begin
  if ! ( ARGV[0].nil? or ARGV[0] == '-' ) # Input
    $stdin.reopen(ARGV[0], "r")
  end
rescue Exception
  STDERR.puts "Failed to open input file: #{$!}"
  raise
end

begin
  if ! ( ARGV[1].nil? or ARGV[1] == '-' ) # Output
    $stdout.reopen(ARGV[1], "w")
  end
rescue Exception
  STDERR.puts "Failed to open output file: #{$!}"
  raise
end

puts <<EOT
# hprcu type

Puppet::Type.newtype(:hprcu) do
	@doc = "" # TODO

	# Type must be ensurable as we must use exists?, because as per p. 46 of 
	# Puppet Types and Providers: properties other than ensure are only 
	# *individually* managed when ensure is set to present and the resource 
	# already exists. When a resource state is absent, Puppet ignores any 
	# specified # resource property.
	ensurable

	newparam(:name, :namevar => true) do
	end

	newparam(:flagchanges) do
		newvalues(:true, :false)
		defaultto(:false)
	end

	newparam(:appendchanges) do
		newvalues(:true, :false)
		defaultto(:false)
	end

	newparam(:flagfile) do
		defaultto('/tmp/hprcu_changes')
		validate do |path|
			if path.include?('..')
				fail("Path to flagfile must not contains '..'")
			elsif ! ( path.start_with?('/tmp') or path.start_with?('/var/tmp') )
				fail("Path to flagfile must start with '/tmp' or '/var/tmp'")
			end
		end
	end

EOT

# Map from (e.g.) 'Intel(R) Hyperthreading Options' to 'intelrhyperthreadingoptions'
# Note that the names of the setters must be 'Puppet-friendly', i.e. valid as per
# grammar.ra in the Puppet source
$map2Valid = {}
def makeValid(invalid)
  if ! $map2Valid.has_key?(invalid)
    # Make into a valid puppet symbol by:
    # 1) Changing to lowercase
    # 2) Removing special characters
    # 3) Prepending 'i' if it starts with digits
    # 4) Removing dots if it ends with dots + numbers
    valid = invalid.downcase.gsub(/[- ()_\/:;,]/,'').sub(/^([0-9]+)/, 'i\1').sub(/\.([0-9]+)$/, '\1')
    $map2Valid[invalid] = valid
  end
  $map2Valid[invalid]
end

$newpropertyTemplate = <<EOT
	newproperty(<%= propertyName %>) do
		newvalues(<%= validValues.join(', ') %>)
	end

EOT

hprcuXml = REXML::Document.new $stdin

hprcuXml.root.elements.each('/hprcu/feature') { |feature| 
  next unless feature.attributes['feature_type'] == 'option'
	propertyName = ''
	validValues = []

	feature.elements.each('feature_name') { |feature_name| 
		propertyName = ':' + makeValid(feature_name.text)
	}

	feature.elements.each('option') { |option| 
		option.elements.each('option_name') { |on| 
#			validValues.push(':' + makeValid(on.text))
			validValues.push('"' + on.text + '"')
		}
	}

	puts ERB.new($newpropertyTemplate).result(binding)
}

puts <<EOT
end
# vim:sw=2:ts=2:et:
EOT

# vim:sw=2:ts=2:et:
